'use strict';
// Slides → PPTX with pptxgenjs. Font name only.

const PptxGenJS = require('pptxgenjs');

const FONT = '맑은 고딕';
const MAX_SLIDES = 30;
const ROWS_PER_SLIDE = 15;

function newDeck() {
  const pptx = new PptxGenJS();
  pptx.layout = 'LAYOUT_WIDE';
  pptx.theme = { headFontFace: FONT, bodyFontFace: FONT };
  return pptx;
}

const out = async (pptx) => Buffer.from(await pptx.write({ outputType: 'nodebuffer' }));

/** slides: [{title, bullets[], notes}] */
async function slidesToPptx(slides) {
  const pptx = newDeck();
  for (const s of slides.slice(0, MAX_SLIDES)) {
    const slide = pptx.addSlide();
    slide.addText(String(s.title || ''), { x: 0.5, y: 0.3, w: 12.3, h: 1, fontFace: FONT, fontSize: 30, bold: true, color: '1F2A4D' });
    const bullets = (s.bullets || []).filter(Boolean);
    if (bullets.length) {
      slide.addText(
        bullets.map((b) => ({ text: String(b), options: { bullet: true } })),
        { x: 0.7, y: 1.5, w: 12, h: 5.5, fontFace: FONT, fontSize: 18, color: '1F2A4D', valign: 'top' },
      );
    }
    if (s.notes) slide.addNotes(String(s.notes));
  }
  return out(pptx);
}

/** One or more slides per sheet; tables split every 15 rows (header repeated). */
async function sheetsToPptx(sheets) {
  const pptx = newDeck();
  let count = 0;
  for (const sh of sheets) {
    if (!sh.rows.length) continue;
    const [head, ...body] = sh.rows;
    const width = Math.max(...sh.rows.map((r) => r.length));
    const pad = (r) => Array.from({ length: width }, (_, i) => String(r[i] ?? ''));
    const chunks = [];
    for (let i = 0; i < Math.max(1, body.length); i += ROWS_PER_SLIDE - 1) chunks.push(body.slice(i, i + ROWS_PER_SLIDE - 1));
    for (const [i, chunk] of chunks.entries()) {
      if (count++ >= MAX_SLIDES) return out(pptx);
      const slide = pptx.addSlide();
      const title = chunks.length > 1 ? `${sh.name} (${i + 1}/${chunks.length})` : sh.name;
      slide.addText(title, { x: 0.5, y: 0.2, w: 12.3, h: 0.7, fontFace: FONT, fontSize: 24, bold: true, color: '1F2A4D' });
      const rows = [pad(head).map((t) => ({ text: t, options: { bold: true, fill: { color: 'EAF0FF' } } })), ...chunk.map((r) => pad(r).map((t) => ({ text: t })))];
      slide.addTable(rows, { x: 0.4, y: 1.0, w: 12.5, fontFace: FONT, fontSize: 11, border: { type: 'solid', pt: 0.75, color: '1F2A4D' }, autoPage: false });
    }
  }
  return out(pptx);
}

module.exports = { slidesToPptx, sheetsToPptx, MAX_SLIDES, ROWS_PER_SLIDE };
