'use strict';
// Plain-text extraction from document bytes. Shared by functions/ and engine/.

const JSZip = require('jszip');

function decodeText(buf) {
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return new TextDecoder('utf-16le').decode(buf.subarray(2));
  if (buf.length >= 2 && buf[0] === 0xfe && buf[1] === 0xff) return new TextDecoder('utf-16be').decode(buf.subarray(2));
  if (buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf) return buf.subarray(3).toString('utf8');
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    return new TextDecoder('euc-kr').decode(buf);
  }
}

function xmlText(s) {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/g, '&');
}

/** Text runs of one XML part, joined per paragraph tag. */
function runsByParagraph(xml, paraTag, runTag) {
  const out = [];
  const paraRe = new RegExp(`<${paraTag}[ >][\\s\\S]*?</${paraTag}>`, 'g');
  const runRe = new RegExp(`<${runTag}(?: [^>]*)?>([\\s\\S]*?)</${runTag}>`, 'g');
  for (const p of xml.match(paraRe) || []) {
    let line = '';
    for (const m of p.matchAll(runRe)) line += xmlText(m[1].replace(/<[^>]+>/g, ''));
    out.push(line);
  }
  return out;
}

const numOf = (name) => Number((name.match(/(\d+)\.xml$/) || [0, 0])[1]);

async function pptxSlides(buf) {
  const zip = await JSZip.loadAsync(buf);
  const names = Object.keys(zip.files)
    .filter((n) => /^ppt\/slides\/slide\d+\.xml$/.test(n))
    .sort((a, b) => numOf(a) - numOf(b));
  const slides = [];
  for (const n of names) {
    const xml = await zip.file(n).async('string');
    const lines = runsByParagraph(xml, 'a:p', 'a:t').filter((l) => l.trim());
    const tables = [];
    for (const tbl of xml.match(/<a:tbl>[\s\S]*?<\/a:tbl>/g) || []) {
      const rows = (tbl.match(/<a:tr[ >][\s\S]*?<\/a:tr>/g) || []).map((tr) =>
        (tr.match(/<a:tc[ >][\s\S]*?<\/a:tc>/g) || []).map((tc) => runsByParagraph(tc, 'a:p', 'a:t').join(' ').trim()),
      );
      if (rows.length) tables.push(rows);
    }
    slides.push({ title: lines[0] || '', lines: lines.slice(1), tables });
  }
  return slides;
}

async function hwpxParagraphs(buf) {
  const zip = await JSZip.loadAsync(buf);
  const names = Object.keys(zip.files)
    .filter((n) => /^Contents\/section\d+\.xml$/i.test(n))
    .sort((a, b) => numOf(a) - numOf(b));
  const lines = [];
  for (const n of names) {
    const xml = await zip.file(n).async('string');
    lines.push(...runsByParagraph(xml, 'hp:p', 'hp:t'));
  }
  return lines;
}

async function xlsxSheets(buf) {
  const ExcelJS = require('exceljs');
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  const sheets = [];
  wb.eachSheet((ws) => {
    const rows = [];
    ws.eachRow({ includeEmpty: false }, (row) => {
      const cells = [];
      for (let c = 1; c <= row.cellCount; c++) cells.push(cellText(row.getCell(c)));
      rows.push(cells);
    });
    sheets.push({ name: ws.name, rows });
  });
  return sheets;
}

function cellText(cell) {
  const v = cell.value;
  if (v == null) return '';
  if (typeof v === 'object') {
    if (v.richText) return v.richText.map((r) => r.text).join('');
    if (v.text != null) return String(v.text);
    if (v.result != null) return String(v.result);
    if (v instanceof Date) return v.toISOString().slice(0, 10);
    return '';
  }
  return String(v);
}

async function pdfText(buf) {
  const { extractText, getDocumentProxy } = await import('unpdf');
  const doc = await getDocumentProxy(new Uint8Array(buf));
  const { totalPages, text } = await extractText(doc, { mergePages: false });
  return { pages: totalPages, text: (Array.isArray(text) ? text : [text]).join('\n\n') };
}

/**
 * Plain text of a file. Throws { code: 'summary-needs-conversion' } for legacy binary formats.
 * PDF without text returns ''.
 */
async function extractText(buf, ext) {
  switch (ext) {
    case 'txt':
    case 'md':
      return decodeText(buf);
    case 'pdf':
      return (await pdfText(buf)).text;
    case 'docx': {
      const mammoth = require('mammoth');
      return (await mammoth.extractRawText({ buffer: buf })).value;
    }
    case 'pptx':
      return (await pptxSlides(buf))
        .map((s) => [s.title, ...s.lines, ...s.tables.flat().map((r) => r.join('\t'))].join('\n'))
        .join('\n\n');
    case 'xlsx':
      return (await xlsxSheets(buf)).map((s) => [s.name, ...s.rows.map((r) => r.join('\t'))].join('\n')).join('\n\n');
    case 'hwpx':
      return (await hwpxParagraphs(buf)).join('\n');
    default: {
      const e = new Error('summary-needs-conversion');
      e.code = 'summary-needs-conversion';
      throw e;
    }
  }
}

module.exports = { decodeText, extractText, pdfText, pptxSlides, hwpxParagraphs, xlsxSheets, runsByParagraph, xmlText };
