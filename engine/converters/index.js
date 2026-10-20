'use strict';
// Routes one job by (source ext, target) following the format table.

const fs = require('node:fs');
const path = require('node:path');
const lo = require('./libreoffice');
const pandoc = require('./pandoc');
const ir = require('./docir');
const { irToDocx, setDocxFont } = require('./docx');
const { tablesToXlsx, tablesFromDelimited } = require('./xlsx');
const { slidesToPptx, sheetsToPptx, MAX_SLIDES } = require('./pptx');
const { irToHwpx } = require('./hwpx');
const { ocrPdf } = require('./ocr');
const inspect = require('./inspect');
const { decodeText, pdfText, pptxSlides, xlsxSheets } = require('../lib/text_extract');
const { SCHEMAS, generateJson, clip } = require('../lib/gemini');
const rules = require('../lib/file_rules');

const err = (code) => Object.assign(new Error(code), { code });
const readBuf = (p) => fs.readFileSync(p);

/** Legacy or Hangul inputs are turned into an OOXML file LibreOffice can write. */
async function modernize(srcPath, ext, workDir) {
  if (['doc', 'hwp', 'hwt', 'hwpx'].includes(ext)) return { p: await lo.to('docx', srcPath, workDir), ext: 'docx' };
  if (ext === 'xls') return { p: await lo.to('xlsx', srcPath, workDir), ext: 'xlsx' };
  if (ext === 'ppt') return { p: await lo.to('pptx', srcPath, workDir), ext: 'pptx' };
  return { p: srcPath, ext };
}

async function docxHtml(p) {
  const mammoth = require('mammoth');
  return (await mammoth.convertToHtml({ buffer: readBuf(p) })).value;
}

function mdHtml(md) {
  const MarkdownIt = require('markdown-it');
  return new MarkdownIt({ html: false, linkify: true }).render(md);
}

function htmlPage(body) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
body{font-family:"Noto Sans CJK KR","Noto Sans CJK JP","Liberation Sans",sans-serif;font-size:11pt;line-height:1.6;}
pre,code{font-family:"Liberation Mono",monospace;}
table{border-collapse:collapse;}td,th{border:1px solid #444;padding:4px 6px;}
</style></head><body>${body}</body></html>`;
}

/** Writes UTF-8 text so LibreOffice reads Korean correctly. */
function utf8Copy(srcPath, workDir) {
  const p = path.join(workDir, 'source-utf8.txt');
  fs.writeFileSync(p, decodeText(readBuf(srcPath)), 'utf8');
  return p;
}

const TXT_INFILTER = 'Text (encoded):UTF8,LF,,';

async function textOf(srcPath, ext, workDir, ai, { ocr = true } = {}) {
  if (ext === 'txt' || ext === 'md') return decodeText(readBuf(srcPath));
  if (ext === 'pdf') {
    const { text } = await pdfText(readBuf(srcPath));
    if (text.trim() || !ocr) return text;
    return ocrPdf(srcPath, workDir, ai);
  }
  const m = await modernize(srcPath, ext, workDir);
  const { extractText } = require('../lib/text_extract');
  return extractText(readBuf(m.p), m.ext);
}

async function aiJson(ai, system, text, schema, validate) {
  await ai.count();
  try {
    return await generateJson({ apiKey: ai.key, model: ai.model, system, parts: [{ text: clip(text) }], schema, validate });
  } catch (e) {
    throw err(e.code === 'ai-unavailable' ? 'ai-unavailable' : 'ai-failed');
  }
}

const PDF_CHUNK_CHARS = 6000;
const PDF_CHUNK_PARALLEL = 4;
const PDF_CHUNK_TIMEOUT_MS = 100000;

/** Splits text on paragraph breaks into pieces of at most `size` characters. */
function chunkText(text, size = PDF_CHUNK_CHARS) {
  const out = [];
  let cur = '';
  for (const para of String(text).replace(/\r\n?/g, '\n').split(/\n{2,}/)) {
    if (cur && cur.length + para.length + 2 > size) {
      out.push(cur);
      cur = '';
    }
    cur += (cur ? '\n\n' : '') + para;
    while (cur.length > size) {
      out.push(cur.slice(0, size));
      cur = cur.slice(size);
    }
  }
  if (cur.trim()) out.push(cur);
  return out;
}

async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/**
 * Long PDFs are structured chunk by chunk so no single Gemini call runs past its time limit.
 * A chunk the AI cannot structure keeps its plain paragraphs, so the conversion still completes.
 */
async function pdfIr(srcPath, workDir, ai) {
  const text = await textOf(srcPath, 'pdf', workDir, ai);
  if (!text.trim()) throw err('no-text-found');
  await ai.count();
  const system =
    'Restructure this extracted PDF text into document blocks (heading with level 1-3, paragraph, list, table). Keep the original language and wording; do not summarize or drop anything. The text may start or end mid-document.';
  const parts = await mapLimit(chunkText(text), PDF_CHUNK_PARALLEL, async (chunk, i) => {
    try {
      const r = await generateJson({
        apiKey: ai.key,
        model: ai.model,
        system,
        parts: [{ text: chunk }],
        schema: SCHEMAS.blocks,
        timeoutMs: PDF_CHUNK_TIMEOUT_MS,
        validate: (v) => {
          if (!Array.isArray(v.blocks)) throw err('ai-bad-json');
        },
      });
      const blocks = ir.irFromAi(r.blocks);
      if (blocks.length) return blocks;
    } catch (e) {
      console.warn(JSON.stringify({ pdfChunk: i, error: e.code || e.message }));
    }
    return ir.irFromText(chunk);
  });
  const blocks = parts.flat();
  if (!blocks.length) throw err('no-text-found');
  return blocks;
}

async function irOf(srcPath, ext, workDir, ai) {
  if (ext === 'md') return ir.irFromHtml(mdHtml(decodeText(readBuf(srcPath))));
  if (ext === 'txt') return ir.irFromText(decodeText(readBuf(srcPath)));
  if (ext === 'pdf') return pdfIr(srcPath, workDir, ai);
  const m = await modernize(srcPath, ext, workDir);
  if (m.ext === 'docx') return ir.irFromHtml(await docxHtml(m.p));
  if (m.ext === 'pptx') return ir.irFromSlides(await pptxSlides(readBuf(m.p)));
  if (m.ext === 'xlsx') return ir.irFromSheets(await xlsxSheets(readBuf(m.p)));
  throw err('unsupported-format');
}

function write(workDir, name, data) {
  const p = path.join(workDir, name);
  fs.writeFileSync(p, data);
  return p;
}

async function toPdf(srcPath, ext, workDir) {
  if (ext === 'md') {
    const html = write(workDir, 'source.html', htmlPage(mdHtml(decodeText(readBuf(srcPath)))));
    return lo.convert(html, 'pdf:writer_web_pdf_Export', 'pdf', workDir);
  }
  if (ext === 'txt') return lo.to('pdf', utf8Copy(srcPath, workDir), workDir, { infilter: TXT_INFILTER });
  return lo.to('pdf', srcPath, workDir);
}

async function toMd(srcPath, ext, workDir, ai) {
  if (ext === 'txt') return decodeText(readBuf(srcPath));
  if (ext === 'pdf') return ir.irToMarkdown(await pdfIr(srcPath, workDir, ai));
  const m = await modernize(srcPath, ext, workDir);
  if (m.ext === 'docx') {
    const TurndownService = require('turndown');
    const { gfm } = require('turndown-plugin-gfm');
    const td = new TurndownService({ headingStyle: 'atx', bulletListMarker: '-', codeBlockStyle: 'fenced' });
    td.use(gfm);
    return td.turndown(await docxHtml(m.p)) + '\n';
  }
  return ir.irToMarkdown(await irOf(m.p, m.ext, workDir, ai));
}

async function toDocx(srcPath, ext, workDir, ai) {
  if (ext === 'md') {
    const out = await pandoc.mdToDocx(srcPath, path.join(workDir, 'pandoc.docx'));
    return write(workDir, 'out.docx', await setDocxFont(readBuf(out)));
  }
  if (['hwp', 'hwpx', 'hwt'].includes(ext)) return lo.to('docx', srcPath, workDir);
  if (ext === 'txt') return lo.to('docx', utf8Copy(srcPath, workDir), workDir, { infilter: TXT_INFILTER });
  return write(workDir, 'out.docx', await irToDocx(await irOf(srcPath, ext, workDir, ai)));
}

async function toPptx(srcPath, ext, workDir, ai) {
  if (ext === 'xls' || ext === 'xlsx') {
    const m = await modernize(srcPath, ext, workDir);
    return write(workDir, 'out.pptx', await sheetsToPptx(await xlsxSheets(readBuf(m.p))));
  }
  const text = await textOf(srcPath, ext, workDir, ai);
  if (!text.trim()) throw err('no-text-found');
  const r = await aiJson(
    ai,
    `Build a presentation from this document: at most ${MAX_SLIDES} slides, each with a short title and 3-6 bullets, optional speaker notes. Use the document's language.`,
    text,
    SCHEMAS.slides,
    (v) => {
      if (!Array.isArray(v.slides) || !v.slides.length) throw err('ai-bad-json');
    },
  );
  return write(workDir, 'out.pptx', await slidesToPptx(r.slides));
}

async function toXlsx(srcPath, ext, workDir, ai) {
  let tables = [];
  if (ext === 'txt') tables = tablesFromDelimited(decodeText(readBuf(srcPath)));
  else if (ext === 'pdf') {
    const text = await textOf(srcPath, 'pdf', workDir, ai);
    if (!text.trim()) throw err('no-text-found');
    const r = await aiJson(
      ai,
      'Extract every table in this document. Each table: sheetName, headers, rows (cells as text). Return an empty list if there are no tables.',
      text,
      SCHEMAS.tables,
      (v) => {
        if (!Array.isArray(v.tables)) throw err('ai-bad-json');
      },
    );
    tables = r.tables.map((t) => ({ sheetName: t.sheetName, rows: [t.headers, ...t.rows] })).filter((t) => t.rows.length > 1);
  } else {
    const m = await modernize(srcPath, ext, workDir);
    if (m.ext === 'pptx') {
      (await pptxSlides(readBuf(m.p))).forEach((s, i) => s.tables.forEach((rows) => tables.push({ sheetName: s.title || `Slide ${i + 1}`, rows })));
    } else {
      tables = ir.tablesFromIr(await irOf(m.p, m.ext, workDir, ai)).map((t) => ({ rows: t.rows }));
    }
  }
  if (!tables.length) throw err('no-table-found');
  return write(workDir, 'out.xlsx', await tablesToXlsx(tables));
}

async function toHwpx(srcPath, ext, workDir, ai, title) {
  return write(workDir, 'out.hwpx', await irToHwpx(await irOf(srcPath, ext, workDir, ai), title));
}

async function toTxt(srcPath, ext, workDir, ai) {
  const text = await textOf(srcPath, ext, workDir, ai);
  if (!text.trim()) throw err('no-text-found');
  return write(workDir, 'out.txt', Buffer.from(text.replace(/\r\n?/g, '\n').replace(/\n/g, '\r\n'), 'utf8'));
}

/**
 * Converts one file. ai = { key, model, visionModel, count() }.
 * Returns { outPath, pageCount, fontSubstituted }.
 */
async function convertFile({ srcPath, ext, target, workDir, ai, title }) {
  const fmt = rules.checkFormat(target, ext);
  if (fmt !== 'ok') throw err(fmt);
  const buf = readBuf(srcPath);
  if (ext === 'hwp' || ext === 'hwt') inspect.checkHwp(buf);
  if (ext === 'hwpx') await inspect.checkHwpx(buf);
  if (ext === 'pdf') await inspect.checkPdf(buf);

  let outPath;
  switch (target) {
    case 'pdf':
      outPath = await toPdf(srcPath, ext, workDir);
      break;
    case 'txt':
      outPath = await toTxt(srcPath, ext, workDir, ai);
      break;
    case 'md':
      outPath = write(workDir, 'out.md', Buffer.from(await toMd(srcPath, ext, workDir, ai), 'utf8'));
      break;
    case 'docx':
      outPath = await toDocx(srcPath, ext, workDir, ai);
      break;
    case 'xlsx':
      outPath = await toXlsx(srcPath, ext, workDir, ai);
      break;
    case 'pptx':
      outPath = await toPptx(srcPath, ext, workDir, ai);
      break;
    case 'hwpx':
      outPath = await toHwpx(srcPath, ext, workDir, ai, title);
      break;
    default:
      throw err('unsupported-format');
  }
  const pageCount = target === 'pdf' ? await inspect.pdfPageCount(readBuf(outPath)) : ext === 'pdf' ? await inspect.pdfPageCount(buf) : null;
  const usesLo = target === 'pdf' || (target === 'docx' && ['hwp', 'hwpx', 'hwt', 'txt'].includes(ext));
  const fontSubstituted = usesLo ? await inspect.usesSubstitutedFonts(buf, ext) : false;
  return { outPath, pageCount, fontSubstituted };
}

module.exports = { convertFile, irOf, textOf, htmlPage, mdHtml, chunkText };
