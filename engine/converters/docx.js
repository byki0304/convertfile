'use strict';
// IR → DOCX with the `docx` library. Font name only (no embedded font files).

const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType } = require('docx');
const JSZip = require('jszip');

const FONT = '맑은 고딕';
const HEADINGS = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3, HeadingLevel.HEADING_4, HeadingLevel.HEADING_5, HeadingLevel.HEADING_6];

const run = (text, opts = {}) => new TextRun({ text, font: { name: FONT, eastAsia: FONT }, ...opts });

function irToDocx(ir) {
  const children = [];
  for (const b of ir) {
    if (b.type === 'heading') {
      children.push(new Paragraph({ heading: HEADINGS[(b.level || 1) - 1], children: [run(b.text, { bold: true })] }));
    } else if (b.type === 'list') {
      b.items.forEach((it, i) => children.push(new Paragraph({ children: [run(b.ordered ? `${i + 1}. ${it}` : `• ${it}`)] })));
    } else if (b.type === 'table') {
      const width = Math.max(...b.rows.map((r) => r.length));
      children.push(
        new Table({
          width: { size: 100, type: WidthType.PERCENTAGE },
          rows: b.rows.map(
            (r) =>
              new TableRow({
                children: Array.from({ length: width }, (_, i) => new TableCell({ children: [new Paragraph({ children: [run(r[i] || '')] })] })),
              }),
          ),
        }),
      );
      children.push(new Paragraph({ children: [] }));
    } else {
      for (const line of String(b.text).split('\n')) children.push(new Paragraph({ children: [run(line)] }));
    }
  }
  const doc = new Document({
    styles: { default: { document: { run: { font: { name: FONT, eastAsia: FONT } } } } },
    sections: [{ children: children.length ? children : [new Paragraph({ children: [] })] }],
  });
  return Packer.toBuffer(doc);
}

/** Sets the default document font name (used after Pandoc). */
async function setDocxFont(buf) {
  const zip = await JSZip.loadAsync(buf);
  const f = zip.file('word/styles.xml');
  if (!f) return buf;
  let xml = await f.async('string');
  const fonts = `<w:rFonts w:ascii="${FONT}" w:hAnsi="${FONT}" w:eastAsia="${FONT}" w:cs="${FONT}"/>`;
  if (/<w:rPrDefault>[\s\S]*?<w:rFonts[^>]*\/>/.test(xml)) {
    xml = xml.replace(/(<w:rPrDefault>[\s\S]*?)<w:rFonts[^>]*\/>/, `$1${fonts}`);
  } else if (/<w:rPrDefault>\s*<w:rPr>/.test(xml)) {
    xml = xml.replace(/<w:rPrDefault>\s*<w:rPr>/, `<w:rPrDefault><w:rPr>${fonts}`);
  }
  zip.file('word/styles.xml', xml);
  return zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
}

module.exports = { irToDocx, setDocxFont };
