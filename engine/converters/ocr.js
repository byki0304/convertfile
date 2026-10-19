'use strict';
// PDF pages without text → page images (pdftoppm) → Gemini vision OCR. Max 20 pages.

const fs = require('node:fs');
const path = require('node:path');
const { run } = require('./proc');
const { SCHEMAS, generateJson } = require('../lib/gemini');

const MAX_PAGES = 20;

async function renderPages(pdfPath, workDir) {
  const dir = path.join(workDir, 'ocr');
  fs.mkdirSync(dir, { recursive: true });
  await run('pdftoppm', ['-r', '110', '-jpeg', '-f', '1', '-l', String(MAX_PAGES), pdfPath, path.join(dir, 'page')]);
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.jpg'))
    .sort()
    .map((f) => path.join(dir, f));
}

/** Returns OCR text, counting one AI call through ai.count(). */
async function ocrPdf(pdfPath, workDir, ai) {
  const images = await renderPages(pdfPath, workDir);
  if (!images.length) return '';
  await ai.count();
  const parts = [
    { text: 'Read all text on these page images in order. Return each page with its number. Keep the original language.' },
    ...images.map((p) => ({ inlineData: { mimeType: 'image/jpeg', data: fs.readFileSync(p).toString('base64') } })),
  ];
  const r = await generateJson({ apiKey: ai.key, model: ai.visionModel, parts, schema: SCHEMAS.ocr });
  return (r.pages || [])
    .sort((a, b) => a.page - b.page)
    .map((p) => p.text)
    .join('\n\n')
    .trim();
}

module.exports = { ocrPdf, renderPages, MAX_PAGES };
