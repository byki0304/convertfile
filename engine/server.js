'use strict';
// Cloud Run convert-engine. POST /convert {uid, conversionId}, called only by Cloud Tasks (OIDC; IAM blocks everyone else).

const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

const { convertFile } = require('./converters');
const { killAll } = require('./converters/proc');
const rules = require('./lib/file_rules');

const KNOWN_ERRORS = new Set([
  'file-too-large', 'unsupported-format', 'same-format', 'encrypted-file', 'protected-hwp', 'no-text-found',
  'no-table-found', 'engine-timeout', 'engine-failed', 'ai-failed', 'ai-unavailable', 'quota-exceeded', 'ai-quota-exceeded',
]);
const JOB_TIMEOUT_MS = 1790 * 1000;
const HOUR = 3600 * 1000;

initializeApp({ storageBucket: process.env.STORAGE_BUCKET || undefined });
const db = getFirestore('convertfile');
const bucket = getStorage().bucket(process.env.STORAGE_BUCKET || undefined);

function seoulDay(date) {
  const k = new Date(date.getTime() + 9 * HOUR);
  return `${k.getUTCFullYear()}${String(k.getUTCMonth() + 1).padStart(2, '0')}${String(k.getUTCDate()).padStart(2, '0')}`;
}

function aiFor(uid) {
  return {
    key: process.env.GEMINI_API_KEY || '',
    model: process.env.GEMINI_MODEL || 'gemini-3.8-flash',
    visionModel: process.env.GEMINI_MODEL_VISION || process.env.GEMINI_MODEL || 'gemini-3.8-flash',
    async count() {
      if (!this.key) throw Object.assign(new Error('ai-unavailable'), { code: 'ai-unavailable' });
      const ref = db.doc(`users/${uid}/usage/${seoulDay(new Date())}`);
      await db.runTransaction(async (tx) => {
        const cur = (await tx.get(ref)).data() || {};
        tx.set(ref, { uid, bytes: cur.bytes || 0, aiCalls: (cur.aiCalls || 0) + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      });
    },
  };
}

/** queued → running, only once (a retried task finds a non-queued job and stops). */
async function claim(ref) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== 'queued') return null;
    tx.update(ref, { status: 'running', startedAt: Timestamp.now() });
    return snap.data();
  });
}

async function finish(ref, fields) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().status !== 'running') return;
    tx.update(ref, { ...fields, finishedAt: Timestamp.now() });
  });
}

async function refund(uid, job) {
  if (!job.bytesCounted) return;
  const ref = db.doc(`users/${uid}/usage/${seoulDay(job.createdAt.toDate())}`);
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur) return;
    tx.update(ref, { bytes: Math.max(0, (cur.bytes || 0) - (job.sourceSize || 0)), updatedAt: FieldValue.serverTimestamp() });
  });
}

function withTimeout(promise, ms) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => {
        killAll();
        reject(Object.assign(new Error('engine-timeout'), { code: 'engine-timeout' }));
      }, ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

async function processJob(uid, conversionId) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid) || !/^[A-Za-z0-9_-]{1,128}$/.test(conversionId)) return 'bad-request';
  const ref = db.doc(`users/${uid}/conversions/${conversionId}`);
  const job = await claim(ref);
  if (!job) return 'skipped';
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'job-'));
  try {
    if (!job.sourcePath || !job.sourcePath.startsWith(`uploads/${uid}/`)) throw Object.assign(new Error(), { code: 'unsupported-format' });
    const srcPath = path.join(workDir, `source.${job.sourceExt}`);
    await pipeline(bucket.file(job.sourcePath).createReadStream(), fs.createWriteStream(srcPath));

    const result = await withTimeout(
      convertFile({ srcPath, ext: job.sourceExt, target: job.targetFormat, workDir, ai: aiFor(uid), title: rules.baseNameOf(job.sourceName) }),
      JOB_TIMEOUT_MS,
    );
    const size = fs.statSync(result.outPath).size;
    if (!(size > 0)) throw Object.assign(new Error('empty output'), { code: 'engine-failed' });

    const outputName = `${rules.baseNameOf(job.sourceName)}.${job.targetFormat}`;
    const outputPath = `outputs/${uid}/${conversionId}/${outputName}`;
    const file = bucket.file(outputPath);
    await bucket.upload(result.outPath, {
      destination: outputPath,
      resumable: size > 8 * 1024 * 1024,
      metadata: { contentType: rules.CONTENT_TYPES[job.targetFormat], contentDisposition: rules.contentDisposition(outputName) },
    });
    const [meta] = await file.getMetadata();
    if (Number(meta.size) !== size) throw Object.assign(new Error('upload size mismatch'), { code: 'engine-failed' });

    await finish(ref, {
      status: 'done',
      errorCode: null,
      outputName,
      outputPath,
      outputSize: size,
      pageCount: result.pageCount ?? null,
      fontSubstituted: !!result.fontSubstituted,
    });
    return 'done';
  } catch (e) {
    const code = KNOWN_ERRORS.has(e.code) ? e.code : 'engine-failed';
    console.error(JSON.stringify({ severity: 'ERROR', conversionId, code, message: String(e.message || e).slice(0, 500) }));
    await finish(ref, { status: 'failed', errorCode: code });
    await refund(uid, job).catch(() => {});
    return 'failed';
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
  }
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/healthz') {
    res.writeHead(200).end('ok');
    return;
  }
  if (req.method !== 'POST' || req.url !== '/convert') {
    res.writeHead(404).end();
    return;
  }
  let body = '';
  req.on('data', (c) => {
    body += c;
    if (body.length > 10000) req.destroy();
  });
  req.on('end', async () => {
    try {
      const { uid, conversionId } = JSON.parse(body || '{}');
      const r = await processJob(String(uid || ''), String(conversionId || ''));
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ result: r }));
    } catch (e) {
      console.error(JSON.stringify({ severity: 'ERROR', message: String(e.message || e).slice(0, 500) }));
      res.writeHead(500).end();
    }
  });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 8080);
  server.listen(port, () => console.log(`convert-engine listening on ${port}`));
}

module.exports = { processJob, seoulDay };
