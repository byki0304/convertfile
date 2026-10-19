'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { getAuth } = require('firebase-admin/auth');

const rules = require('./lib/file_rules');
const { SCHEMAS, generateJson, clip } = require('./lib/gemini');
const { extractText } = require('./lib/text_extract');
const { M, MENU_NAMES, pick } = require('./lib/messages');

const REGION = 'asia-northeast3';
const PRIMARY_DB = 'convertfile';
const BACKUP_DB = 'convertfile-backup';
const HOUR = 3600 * 1000;

const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
const EXCHANGE_RATE_API_KEY = defineSecret('EXCHANGE_RATE_API_KEY');

initializeApp();
setGlobalOptions({ region: REGION, maxInstances: 20 });

const db = getFirestore(PRIMARY_DB);
const backupDb = getFirestore(BACKUP_DB);
const bucket = () => getStorage().bucket();

const env = {
  model: () => process.env.GEMINI_MODEL || 'gemini-3.8-flash',
  engineUrl: () => (process.env.ENGINE_URL || '').replace(/\/$/, ''),
  tasksSa: () => process.env.TASKS_INVOKER_SA || '',
  project: () => process.env.GCLOUD_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId,
};

const USER_COLLECTIONS = ['conversions', 'turns', 'usage'];
const LANGS = ['ko', 'en', 'ja'];

// ---------- helpers ----------

function fail(code, httpsCode = 'failed-precondition') {
  throw new HttpsError(httpsCode, code, { code });
}

function who(req) {
  if (!req.auth) fail('unauthenticated', 'unauthenticated');
  return { uid: req.auth.uid, guest: req.auth.token?.firebase?.sign_in_provider === 'anonymous' };
}

/** yyyyMMdd in Asia/Seoul. */
function seoulDay(date = new Date()) {
  const k = new Date(date.getTime() + 9 * HOUR);
  return `${k.getUTCFullYear()}${String(k.getUTCMonth() + 1).padStart(2, '0')}${String(k.getUTCDate()).padStart(2, '0')}`;
}

const usageRef = (uid, day = seoulDay()) => db.doc(`users/${uid}/usage/${day}`);
const convRef = (uid, id) => db.doc(`users/${uid}/conversions/${id}`);
const turnRef = (uid, id) => db.doc(`users/${uid}/turns/${id}`);

async function audit(action, actorUid, targetId, changedFields) {
  await db.collection('audit').add({
    action,
    actorUid,
    targetUid: actorUid,
    targetId: targetId || null,
    changedFields: changedFields || [],
    at: FieldValue.serverTimestamp(),
  });
}

/** Adds bytes to today's usage in a transaction, rejecting when over the daily limit. */
async function addBytes(uid, guest, bytes) {
  const ref = usageRef(uid);
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data() || {};
    const used = cur.bytes || 0;
    if (used + bytes > rules.dailyLimit(guest)) fail('quota-exceeded', 'resource-exhausted');
    tx.set(ref, { uid, bytes: used + bytes, aiCalls: cur.aiCalls || 0, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
}

async function refundBytes(uid, day, bytes) {
  const ref = usageRef(uid, day);
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur) return;
    tx.update(ref, { bytes: Math.max(0, (cur.bytes || 0) - bytes), updatedAt: FieldValue.serverTimestamp() });
  });
}

async function ensureAiLeft(uid, guest, need = 1) {
  const cur = (await usageRef(uid).get()).data() || {};
  if ((cur.aiCalls || 0) + need > rules.aiLimit(guest)) fail('ai-quota-exceeded', 'resource-exhausted');
}

/** Counts one AI call; the automatic retry inside generateJson is not counted. */
async function addAiCall(uid, guest) {
  const ref = usageRef(uid);
  await db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data() || {};
    const n = cur.aiCalls || 0;
    if (n + 1 > rules.aiLimit(guest)) fail('ai-quota-exceeded', 'resource-exhausted');
    tx.set(ref, { uid, bytes: cur.bytes || 0, aiCalls: n + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
}

function aiKey() {
  try {
    return GEMINI_API_KEY.value() || '';
  } catch {
    return '';
  }
}

function checkUploadPath(uid, path) {
  if (typeof path !== 'string' || !path.startsWith(`uploads/${uid}/`) || path.includes('..')) fail('unsupported-format', 'permission-denied');
}

/** Size and magic-byte check of an uploaded file. */
async function inspectUpload(uid, guest, path, name) {
  checkUploadPath(uid, path);
  const ext = rules.extOf(name);
  if (!rules.KNOWN.includes(ext) || rules.extOf(path) !== ext) fail('unsupported-format');
  const file = bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) fail('engine-failed', 'not-found');
  const [meta] = await file.getMetadata();
  const size = Number(meta.size || 0);
  if (size <= 0) fail('unsupported-format');
  if (size > rules.fileLimit(guest)) fail('file-too-large');
  const head = await readHead(file, 4096);
  const magic = rules.checkMagic(ext, head);
  if (magic !== 'ok') fail(magic);
  return { ext, size, file };
}

function readHead(file, n) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    file
      .createReadStream({ start: 0, end: n - 1 })
      .on('data', (c) => chunks.push(c))
      .on('error', reject)
      .on('end', () => resolve(Buffer.concat(chunks)));
  });
}

async function downloadLimited(file, size) {
  if (size > rules.LIMITS.summarySourceBytes) {
    const e = new Error('source-too-large-for-summary');
    e.code = 'source-too-large-for-summary';
    throw e;
  }
  const [buf] = await file.download();
  return buf;
}

async function deleteFiles(paths) {
  await Promise.all(paths.filter(Boolean).map((p) => bucket().file(p).delete({ ignoreNotFound: true }).catch(() => {})));
}

/** Removes expired conversions and turns (TTL is only a backup for this). */
async function cleanupExpired(uid) {
  const now = Timestamp.now();
  const conv = await db.collection(`users/${uid}/conversions`).where('expireAt', '<=', now).limit(100).get();
  for (const d of conv.docs) {
    const c = d.data();
    await deleteFiles([c.sourcePath, c.outputPath]);
    await d.ref.delete();
  }
  const turns = await db.collection(`users/${uid}/turns`).where('expireAt', '<=', now).limit(100).get();
  for (const d of turns.docs) {
    const t = d.data();
    if (t.filePath) await deleteFiles([t.filePath]);
    await d.ref.delete();
  }
}

function toPlain(data) {
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (v instanceof Timestamp) out[k] = v.toMillis();
    else if (v && typeof v === 'object' && !Array.isArray(v)) out[k] = toPlain(v);
    else out[k] = v;
  }
  return out;
}

async function enqueue(uid, conversionId) {
  const url = env.engineUrl();
  const sa = env.tasksSa();
  if (!url || !sa) throw new Error('engine-not-configured');
  const { CloudTasksClient } = require('@google-cloud/tasks');
  const client = new CloudTasksClient();
  const parent = client.queuePath(env.project(), REGION, 'convert-queue');
  await client.createTask({
    parent,
    task: {
      httpRequest: {
        httpMethod: 'POST',
        url: `${url}/convert`,
        headers: { 'Content-Type': 'application/json' },
        body: Buffer.from(JSON.stringify({ uid, conversionId })).toString('base64'),
        oidcToken: { serviceAccountEmail: sa, audience: url },
      },
      dispatchDeadline: { seconds: 1800 },
    },
  });
}

const callOpts = { timeoutSeconds: 300, memory: '1GiB' };

// ---------- conversions ----------

exports.requestConversion = onCall(callOpts, async (req) => {
  const { uid, guest } = who(req);
  const { path, name, target, turnId } = req.data || {};
  if (typeof name !== 'string' || !name || name.length > 255) fail('unsupported-format', 'invalid-argument');
  if (!rules.TARGETS.includes(target)) fail('unsupported-format', 'invalid-argument');
  await cleanupExpired(uid).catch((e) => logger.warn('cleanup', e.message));

  const ext = rules.extOf(name);
  const fmt = rules.checkFormat(target, ext);
  if (fmt !== 'ok') fail(fmt);
  const { size } = await inspectUpload(uid, guest, path, name);
  if (rules.needsAi(target, ext)) {
    if (!aiKey()) fail('ai-unavailable');
    await ensureAiLeft(uid, guest);
  }

  let counted = false;
  if (typeof turnId === 'string' && turnId) {
    const t = (await turnRef(uid, turnId).get()).data();
    counted = !!(t && t.filePath === path && t.fileCounted);
  }
  if (!counted) await addBytes(uid, guest, size);

  const now = Timestamp.now();
  const ref = db.collection(`users/${uid}/conversions`).doc();
  await ref.set({
    uid,
    sourceName: name,
    sourceExt: ext,
    sourceSize: size,
    sourcePath: path,
    targetFormat: target,
    mode: rules.modeOf(target, ext),
    engine: rules.engineOf(target, ext),
    status: 'queued',
    errorCode: null,
    outputName: `${rules.baseNameOf(name)}.${target}`,
    outputPath: null,
    outputSize: null,
    pageCount: null,
    summaryLines: [],
    fontSubstituted: false,
    bytesCounted: !counted,
    createdAt: now,
    startedAt: null,
    finishedAt: null,
    expireAt: Timestamp.fromMillis(now.toMillis() + rules.LIMITS.retentionHours * HOUR),
  });

  try {
    await enqueue(uid, ref.id);
  } catch (e) {
    logger.error('enqueue failed', e.message);
    await ref.update({ status: 'failed', errorCode: 'engine-failed', finishedAt: Timestamp.now() });
    if (!counted) await refundBytes(uid, seoulDay(now.toDate()), size);
  }
  return { conversionId: ref.id };
});

exports.getDownloadUrl = onCall(async (req) => {
  const { uid } = who(req);
  const id = req.data?.conversionId;
  if (typeof id !== 'string') fail('engine-failed', 'invalid-argument');
  const c = (await convRef(uid, id).get()).data();
  if (!c || c.status !== 'done' || !(c.outputSize > 0) || !c.outputPath) fail('engine-failed', 'not-found');
  if (c.expireAt && c.expireAt.toMillis() <= Date.now()) fail('engine-failed', 'not-found');
  const [url] = await bucket()
    .file(c.outputPath)
    .getSignedUrl({
      version: 'v4',
      action: 'read',
      expires: Date.now() + 10 * 60 * 1000,
      responseDisposition: rules.contentDisposition(c.outputName),
    });
  return { url };
});

exports.summarizeConversion = onCall({ ...callOpts, memory: '2GiB', secrets: [GEMINI_API_KEY] }, async (req) => {
  const { uid, guest } = who(req);
  const id = req.data?.conversionId;
  if (typeof id !== 'string') fail('engine-failed', 'invalid-argument');
  const ref = convRef(uid, id);
  const c = (await ref.get()).data();
  if (!c || c.status !== 'done' || !c.outputPath) fail('engine-failed', 'not-found');
  if (!aiKey()) fail('ai-unavailable');
  await ensureAiLeft(uid, guest);
  const file = bucket().file(c.outputPath);
  let text;
  try {
    const buf = await downloadLimited(file, c.outputSize || 0);
    text = await extractText(buf, c.targetFormat);
  } catch (e) {
    fail(e.code || 'engine-failed');
  }
  if (!text || !text.trim()) fail('no-text-found');
  const lines = await summarize(uid, guest, text, req.data?.lang);
  await ref.update({ summaryLines: lines });
  return { summaryLines: lines };
});

async function summarize(uid, guest, text, lang) {
  const language = { ko: 'Korean', en: 'English', ja: 'Japanese' }[lang] || 'the language of the document';
  await addAiCall(uid, guest);
  try {
    const r = await generateJson({
      apiKey: aiKey(),
      model: env.model(),
      system: `Summarize the document in exactly 3 short lines in ${language}. Also give up to 5 keywords.`,
      parts: [{ text: clip(text) }],
      schema: SCHEMAS.summary,
      validate: (v) => {
        if (!Array.isArray(v.lines) || v.lines.length === 0) throw Object.assign(new Error(), { code: 'ai-bad-json' });
      },
    });
    return r.lines.slice(0, 3).map((l) => String(l).slice(0, 300));
  } catch (e) {
    fail(e.code === 'ai-unavailable' ? 'ai-unavailable' : 'ai-failed');
  }
}

// ---------- AI home ----------

function menuContext() {
  const lines = rules.TARGETS.map((t) => `to_${t}: accepts ${rules.ACCEPTED[t].join(', ')}`);
  lines.push('pdf_merge: merge several PDF files (pdf only)', 'pdf_edit: delete, reorder, extract, print PDF pages (pdf only)');
  lines.push('calculator: calcMode basic|scientific|fx|business; calcInput is the expression or amount; fxCurrency for fx');
  lines.push('summarize: summarize the attached file', 'general: any other question; answer in answerText');
  return lines.join('\n');
}

exports.submitPrompt = onCall({ ...callOpts, memory: '2GiB', secrets: [GEMINI_API_KEY] }, async (req) => {
  const { uid, guest } = who(req);
  const d = req.data || {};
  const userText = String(d.text || '').slice(0, 4000);
  const lang = LANGS.includes(d.lang) ? d.lang : 'ko';
  const isVoice = d.isVoice === true;
  const hasFile = typeof d.filePath === 'string' && d.filePath;
  if (!userText.trim() && !hasFile) fail('empty', 'invalid-argument');
  await cleanupExpired(uid).catch((e) => logger.warn('cleanup', e.message));

  if (!aiKey()) fail('ai-unavailable');
  await ensureAiLeft(uid, guest);

  let upload = null;
  if (hasFile) {
    if (typeof d.fileName !== 'string' || !d.fileName) fail('unsupported-format', 'invalid-argument');
    upload = await inspectUpload(uid, guest, d.filePath, d.fileName);
    await addBytes(uid, guest, upload.size);
  }

  const recent = await db.collection(`users/${uid}/turns`).orderBy('createdAt', 'desc').limit(3).get();
  const history = recent.docs
    .map((x) => x.data())
    .reverse()
    .map((t) => `user: ${clip(t.userText, 500)}\nassistant: ${clip(t.aiText, 500)}`)
    .join('\n');
  const now = new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Seoul' });
  const fileLine = upload ? `Attached file: ${d.fileName} (ext ${upload.ext}, ${upload.size} bytes)` : 'Attached file: none';
  const system = [
    'You route requests for a document conversion workbench. Choose exactly one targetMenu.',
    'Pick a to_* menu only when the user wants a file converted to that result format.',
    'summaryText: one short sentence describing the request. answerText: only for general, a helpful answer.',
    `Answer in ${{ ko: 'Korean', en: 'English', ja: 'Japanese' }[lang]}.`,
    `Now (Asia/Seoul): ${now}`,
    'Menus:',
    menuContext(),
    fileLine,
    history ? `Recent conversation:\n${history}` : '',
  ].join('\n');

  await addAiCall(uid, guest);
  let intent = null;
  try {
    intent = await generateJson({
      apiKey: aiKey(),
      model: env.model(),
      system,
      parts: [{ text: userText || '(file only)' }],
      schema: SCHEMAS.home,
      validate: (v) => {
        if (!v || typeof v.targetMenu !== 'string' || typeof v.summaryText !== 'string') throw Object.assign(new Error(), { code: 'ai-bad-json' });
      },
    });
  } catch (e) {
    if (e.code === 'ai-unavailable') fail('ai-unavailable');
    intent = null;
  }

  const turn = {
    uid,
    userText,
    aiText: '',
    isVoice,
    fileName: upload ? d.fileName : null,
    filePath: upload ? d.filePath : null,
    fileCounted: !!upload,
    targetMenu: intent?.targetMenu || 'general',
    routeCard: null,
    summaryLines: [],
    createdAt: Timestamp.now(),
    expireAt: guest ? Timestamp.fromMillis(Date.now() + rules.LIMITS.retentionHours * HOUR) : null,
    userHidden: false,
    aiHidden: false,
  };

  if (!intent) {
    turn.aiText = pick(M.intentFail, lang);
  } else {
    await resolveIntent(turn, intent, upload, lang, uid, guest);
  }
  turn.aiText = String(turn.aiText || '').slice(0, 8000);
  const ref = await db.collection(`users/${uid}/turns`).add(turn);
  return { turnId: ref.id };
});

async function resolveIntent(turn, intent, upload, lang, uid, guest) {
  const menu = intent.targetMenu;
  if (menu.startsWith('to_')) {
    const target = menu.slice(3);
    if (!upload) {
      turn.aiText = pick(M.uploadToConvert, lang);
      turn.routeCard = { targetMenu: menu, canConvert: false };
      return;
    }
    const r = rules.checkFormat(target, upload.ext);
    if (r === 'same-format') turn.aiText = pick(M.sameFormat(upload.ext.toUpperCase()), lang);
    else if (r !== 'ok') turn.aiText = pick(M.unsupported(rules.ACCEPTED[target].map((x) => x.toUpperCase()).join(', ')), lang);
    else {
      turn.aiText = pick(M.routeAsk(MENU_NAMES[menu]), lang);
      turn.routeCard = { targetMenu: menu, sourceExt: upload.ext, canConvert: true };
    }
    return;
  }
  if (menu === 'pdf_merge' || menu === 'pdf_edit') {
    if (upload && upload.ext !== 'pdf') {
      turn.aiText = pick(M.pdfOnly, lang);
      return;
    }
    turn.aiText = pick(M.routeOpen(MENU_NAMES[menu]), lang);
    turn.routeCard = { targetMenu: menu, sourceExt: upload ? 'pdf' : null, canConvert: false };
    return;
  }
  if (menu === 'calculator') {
    const mode = intent.calcMode;
    const input = String(intent.calcInput || '').slice(0, 200);
    const valid = ['basic', 'scientific', 'fx', 'business'].includes(mode) && (mode === 'business' || input.trim());
    if (!valid) {
      turn.aiText = pick(M.calcFail, lang);
      return;
    }
    turn.aiText = pick(M.routeOpen(MENU_NAMES.calculator), lang);
    turn.routeCard = { targetMenu: menu, calcMode: mode, calcInput: input, fxCurrency: intent.fxCurrency || null };
    return;
  }
  if (menu === 'summarize') {
    if (!upload) {
      turn.aiText = pick(M.summarizeNeedsFile, lang);
      return;
    }
    let text = '';
    try {
      const buf = await downloadLimited(upload.file, upload.size);
      text = await extractText(buf, upload.ext);
    } catch (e) {
      if (e.code === 'summary-needs-conversion') turn.aiText = pick(M.needsConversion, lang);
      else if (e.code === 'source-too-large-for-summary') turn.aiText = pick(M.tooLargeToSummarize, lang);
      else turn.aiText = pick(M.generalFail, lang);
      return;
    }
    if (!text.trim()) {
      turn.aiText = pick(M.noText, lang);
      return;
    }
    try {
      turn.summaryLines = await summarize(uid, guest, text, lang);
      turn.aiText = intent.summaryText || '';
    } catch (e) {
      if (e instanceof HttpsError && e.details?.code === 'ai-quota-exceeded') throw e;
      turn.aiText = pick(M.generalFail, lang);
    }
    return;
  }
  turn.aiText = intent.answerText && intent.answerText.trim() ? intent.answerText : pick(M.generalFail, lang);
}

exports.hideTurnParts = onCall(async (req) => {
  const { uid } = who(req);
  const parts = Array.isArray(req.data?.parts) ? req.data.parts.slice(0, 400) : [];
  for (const p of parts) {
    if (typeof p?.turnId !== 'string' || !['user', 'ai'].includes(p.part)) continue;
    const ref = turnRef(uid, p.turnId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const t = snap.data();
      const userHidden = t.userHidden || p.part === 'user';
      const aiHidden = t.aiHidden || p.part === 'ai';
      if (userHidden && aiHidden) tx.delete(ref);
      else tx.update(ref, { userHidden, aiHidden });
    });
  }
  await audit('hideTurnParts', uid, null, ['userHidden', 'aiHidden']);
  return { ok: true };
});

exports.deleteByIds = onCall(async (req) => {
  const { uid } = who(req);
  const ids = Array.isArray(req.data?.conversionIds) ? req.data.conversionIds.filter((x) => typeof x === 'string').slice(0, 400) : [];
  let deleted = 0;
  let skipped = 0;
  for (const id of ids) {
    const ref = convRef(uid, id);
    const c = (await ref.get()).data();
    if (!c) continue;
    if (c.status === 'running') {
      skipped++;
      continue;
    }
    await deleteFiles([c.sourcePath, c.outputPath]);
    await ref.delete();
    deleted++;
  }
  const turnIds = Array.isArray(req.data?.turnIds) ? req.data.turnIds.filter((x) => typeof x === 'string').slice(0, 400) : [];
  for (const id of turnIds) await turnRef(uid, id).delete();
  if (req.data?.allTurns === true) {
    for (;;) {
      const snap = await db.collection(`users/${uid}/turns`).limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((x) => batch.delete(x.ref));
      await batch.commit();
    }
  }
  if (deleted || turnIds.length || req.data?.allTurns) await audit('deleteByIds', uid, null, ['conversions', 'turns']);
  return { deleted, skipped };
});

exports.withdraw = onCall({ timeoutSeconds: 540, memory: '1GiB' }, async (req) => {
  const { uid } = who(req);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  for (const field of ['actorUid', 'targetUid']) {
    for (;;) {
      const snap = await db.collection('audit').where(field, '==', uid).limit(400).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((x) => batch.delete(x.ref));
      await batch.commit();
    }
  }
  await bucket().deleteFiles({ prefix: `uploads/${uid}/`, force: true });
  await bucket().deleteFiles({ prefix: `outputs/${uid}/`, force: true });
  await backupDb.recursiveDelete(backupDb.doc(`users/${uid}`));
  await getAuth().deleteUser(uid);
  return { ok: true };
});

// ---------- exchange rates ----------

const FX = ['USD', 'EUR', 'JPY', 'CNY', 'GBP', 'HKD', 'SGD', 'AUD'];

exports.getExchangeRates = onCall({ secrets: [EXCHANGE_RATE_API_KEY] }, async (req) => {
  who(req);
  const ref = db.doc('fx_cache/latest');
  const cached = (await ref.get()).data();
  if (cached && Date.now() - cached.fetchedAt.toMillis() < 60 * 60 * 1000) {
    return { base: 'KRW', rates: cached.rates, fetchedAt: cached.fetchedAt.toMillis() };
  }
  let key = '';
  try {
    key = EXCHANGE_RATE_API_KEY.value() || '';
  } catch {
    key = '';
  }
  try {
    if (!key) throw new Error('fx-unavailable');
    const res = await fetch(`https://v6.exchangerate-api.com/v6/${encodeURIComponent(key)}/latest/KRW`);
    const json = await res.json();
    if (!res.ok || json.result !== 'success') throw new Error('fx-failed');
    const rates = {};
    for (const c of FX) {
      const perKrw = json.conversion_rates?.[c];
      if (perKrw > 0) rates[c] = 1 / perKrw;
    }
    const fetchedAt = Timestamp.now();
    await ref.set({ base: 'KRW', rates, fetchedAt });
    return { base: 'KRW', rates, fetchedAt: fetchedAt.toMillis() };
  } catch (e) {
    if (cached) return { base: 'KRW', rates: cached.rates, fetchedAt: cached.fetchedAt.toMillis() };
    fail(e.message === 'fx-unavailable' ? 'fx-unavailable' : 'fx-failed', 'unavailable');
  }
});

// ---------- backup DB ----------

exports.mirrorToBackup = onDocumentWritten(
  { document: 'users/{uid}/{collection}/{docId}', database: PRIMARY_DB, region: REGION },
  async (event) => {
    const { uid, collection, docId } = event.params;
    if (!USER_COLLECTIONS.includes(collection)) return;
    const eventTime = Timestamp.fromDate(new Date(event.time));
    const ref = backupDb.doc(`users/${uid}/${collection}/${docId}`);
    const after = event.data?.after;
    await backupDb.runTransaction(async (tx) => {
      const cur = await tx.get(ref);
      if (cur.exists && cur.data().mirrorEventTime && cur.data().mirrorEventTime.toMillis() > eventTime.toMillis()) return;
      if (after && after.exists) tx.set(ref, { ...after.data(), mirrorEventTime: eventTime, mirroredAt: FieldValue.serverTimestamp() });
      else tx.delete(ref);
    });
    await backupDb.doc(`users/${uid}`).set({ lastMirroredAt: FieldValue.serverTimestamp() }, { merge: true });
  },
);

exports.readBackup = onCall(async (req) => {
  const { uid } = who(req);
  const col = req.data?.collection;
  if (!['conversions', 'turns'].includes(col)) fail('engine-failed', 'invalid-argument');
  const snap = await backupDb.collection(`users/${uid}/${col}`).orderBy('createdAt', 'desc').limit(100).get();
  const now = Date.now();
  const docs = snap.docs
    .map((x) => ({ id: x.id, ...toPlain(x.data()) }))
    .filter((x) => !(typeof x.expireAt === 'number' && x.expireAt <= now))
    .map(({ mirrorEventTime, mirroredAt, sourcePath, outputPath, filePath, ...rest }) => rest);
  return { docs };
});

async function countUser(store, uid) {
  let n = 0;
  for (const c of USER_COLLECTIONS) n += (await store.collection(`users/${uid}/${c}`).count().get()).data().count;
  return n;
}

exports.dbStatus = onCall(async (req) => {
  const { uid } = who(req);
  const [primaryCount, backupCount, meta] = await Promise.all([
    countUser(db, uid),
    countUser(backupDb, uid),
    backupDb.doc(`users/${uid}`).get(),
  ]);
  const last = meta.data()?.lastMirroredAt;
  return { primaryCount, backupCount, lastMirroredAt: last ? last.toMillis() : null };
});

exports.syncBackup = onCall({ timeoutSeconds: 540 }, async (req) => {
  const { uid } = who(req);
  const now = Timestamp.now();
  for (const c of USER_COLLECTIONS) {
    const [src, dst] = await Promise.all([db.collection(`users/${uid}/${c}`).get(), backupDb.collection(`users/${uid}/${c}`).get()]);
    const ids = new Set(src.docs.map((x) => x.id));
    let batch = backupDb.batch();
    let n = 0;
    const flush = async () => {
      if (n) await batch.commit();
      batch = backupDb.batch();
      n = 0;
    };
    for (const x of src.docs) {
      batch.set(backupDb.doc(`users/${uid}/${c}/${x.id}`), { ...x.data(), mirrorEventTime: now, mirroredAt: now });
      if (++n >= 400) await flush();
    }
    for (const x of dst.docs) {
      if (ids.has(x.id)) continue;
      batch.delete(x.ref);
      if (++n >= 400) await flush();
    }
    await flush();
  }
  await backupDb.doc(`users/${uid}`).set({ lastMirroredAt: now }, { merge: true });
  return { ok: true };
});