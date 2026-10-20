'use strict';
// Encryption / protection checks and font-substitution detection.

const JSZip = require('jszip');

const err = (code) => Object.assign(new Error(code), { code });

/** HWP 5.0 FileHeader flags: bit 1 password, bit 2 distribution (protected) document. */
function checkHwp(buf) {
  const CFB = require('cfb');
  let header;
  try {
    const doc = CFB.read(buf, { type: 'buffer' });
    header = CFB.find(doc, 'FileHeader');
  } catch {
    throw err('engine-failed');
  }
  if (!header || !header.content) throw err('engine-failed');
  const c = Buffer.from(header.content);
  const flags = c.readUInt32LE(36);
  if (flags & 0x2) throw err('encrypted-file');
  if (flags & 0x4) throw err('protected-hwp');
}

async function checkHwpx(buf) {
  const zip = await JSZip.loadAsync(buf);
  const manifest = zip.file('META-INF/manifest.xml');
  if (manifest && /encryption-data/i.test(await manifest.async('string'))) throw err('encrypted-file');
}

async function checkPdf(buf) {
  const { PDFDocument } = require('pdf-lib');
  try {
    const doc = await PDFDocument.load(buf, { updateMetadata: false });
    return doc.getPageCount();
  } catch (e) {
    if (/encrypt/i.test(String(e && (e.name + e.message)))) return openablePdfPages(buf);
    throw err('engine-failed');
  }
}

/** Permission-only encryption (empty open password) is readable; only an open password blocks conversion. */
async function openablePdfPages(buf) {
  const { getDocumentProxy } = await import('unpdf');
  let doc;
  try {
    doc = await getDocumentProxy(new Uint8Array(buf));
  } catch (e) {
    if (e && e.name === 'PasswordException') throw err('encrypted-file');
    throw err('engine-failed');
  }
  return doc.numPages;
}

async function pdfPageCount(buf) {
  const { PDFDocument } = require('pdf-lib');
  try {
    return (await PDFDocument.load(buf, { ignoreEncryption: true, updateMetadata: false })).getPageCount();
  } catch {
    return null;
  }
}

/** Fonts in the substitution table (engine/config/fontsubst.xcu). */
const SUBSTITUTED = [
  '함초롬바탕', '바탕', '바탕체', '궁서', '신명조', 'HY신명조', '한컴바탕',
  '함초롬돋움', '돋움', '돋움체', '굴림', '굴림체', '맑은 고딕', '한컴돋움', 'HY견고딕', 'HY중고딕',
  'MS Mincho', 'Yu Mincho', 'MS Gothic', 'Meiryo', 'Yu Gothic',
  'Arial', 'Helvetica', 'Times New Roman', 'Courier New', 'Calibri', 'Cambria',
  'Malgun Gothic', 'Batang', 'Dotum', 'Gulim', 'Gungsuh', 'HCR Batang', 'HCR Dotum',
];

/** Best-effort: true when the source names a font that LibreOffice will replace with a free font. */
async function usesSubstitutedFonts(buf, ext) {
  try {
    if (['docx', 'pptx', 'xlsx', 'hwpx'].includes(ext)) {
      const zip = await JSZip.loadAsync(buf);
      const names = Object.keys(zip.files).filter((n) => /(fontTable|theme\d*|header|styles|section\d+)\.xml$/i.test(n) || /slide\d+\.xml$/.test(n));
      for (const n of names.slice(0, 40)) {
        const xml = await zip.file(n).async('string');
        if (SUBSTITUTED.some((f) => xml.includes(`"${f}"`))) return true;
      }
      return false;
    }
    if (['hwp', 'hwt', 'doc', 'xls', 'ppt'].includes(ext)) {
      const sample = buf.subarray(0, Math.min(buf.length, 4 * 1024 * 1024));
      return SUBSTITUTED.some((f) => sample.includes(Buffer.from(f, 'utf16le')));
    }
  } catch {
    return false;
  }
  return false;
}

module.exports = { checkHwp, checkHwpx, checkPdf, pdfPageCount, usesSubstitutedFonts, SUBSTITUTED };
