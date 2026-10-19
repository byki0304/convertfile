'use strict';
// Document intermediate representation: [{type: heading|paragraph|list|table, level, text, items, rows, ordered}]

const { parse } = require('node-html-parser');

const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim();

function irFromHtml(html) {
  const root = parse(html, { blockTextElements: { script: false, style: false } });
  const blocks = [];
  const walk = (node) => {
    for (const el of node.childNodes) {
      if (el.nodeType === 3) {
        const t = clean(el.text);
        if (t) blocks.push({ type: 'paragraph', text: t });
        continue;
      }
      if (el.nodeType !== 1) continue;
      const tag = el.tagName.toLowerCase();
      if (/^h[1-6]$/.test(tag)) {
        const t = clean(el.text);
        if (t) blocks.push({ type: 'heading', level: Number(tag[1]), text: t });
      } else if (tag === 'p' || tag === 'pre' || tag === 'blockquote') {
        const t = tag === 'pre' ? el.text.replace(/\s+$/, '') : clean(el.text);
        if (t) blocks.push({ type: 'paragraph', text: t });
      } else if (tag === 'ul' || tag === 'ol') {
        const items = el.childNodes.filter((c) => c.nodeType === 1 && c.tagName.toLowerCase() === 'li').map((li) => clean(li.text));
        if (items.length) blocks.push({ type: 'list', ordered: tag === 'ol', items });
      } else if (tag === 'table') {
        const rows = el
          .querySelectorAll('tr')
          .map((tr) => tr.childNodes.filter((c) => c.nodeType === 1 && /^t[dh]$/i.test(c.tagName)).map((c) => clean(c.text)));
        if (rows.length) blocks.push({ type: 'table', rows });
      } else if (tag === 'br' || tag === 'hr' || tag === 'img') {
        continue;
      } else {
        walk(el);
      }
    }
  };
  walk(root.querySelector('body') || root);
  return blocks;
}

function irFromText(text) {
  return String(text || '')
    .replace(/\r\n?/g, '\n')
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => ({ type: 'paragraph', text: p }));
}

function irFromSlides(slides) {
  const blocks = [];
  slides.forEach((s, i) => {
    blocks.push({ type: 'heading', level: 2, text: s.title || `Slide ${i + 1}` });
    if (s.lines.length) blocks.push({ type: 'list', ordered: false, items: s.lines });
    for (const rows of s.tables || []) blocks.push({ type: 'table', rows });
  });
  return blocks;
}

function irFromSheets(sheets) {
  const blocks = [];
  for (const s of sheets) {
    if (!s.rows.length) continue;
    blocks.push({ type: 'heading', level: 2, text: s.name });
    blocks.push({ type: 'table', rows: s.rows });
  }
  return blocks;
}

/** Normalizes AI "blocks" output. */
function irFromAi(blocks) {
  return (blocks || [])
    .map((b) => {
      if (b.type === 'heading') return { type: 'heading', level: Math.min(6, Math.max(1, b.level || 1)), text: clean(b.text) };
      if (b.type === 'list') return { type: 'list', ordered: false, items: (b.items || []).map(clean).filter(Boolean) };
      if (b.type === 'table') return { type: 'table', rows: (b.rows || []).map((r) => r.map(clean)) };
      return { type: 'paragraph', text: String(b.text || '').trim() };
    })
    .filter((b) => (b.type === 'list' ? b.items.length : b.type === 'table' ? b.rows.length : b.text));
}

const mdCell = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');

function mdTable(rows) {
  const width = Math.max(...rows.map((r) => r.length));
  const pad = (r) => [...r, ...Array(width - r.length).fill('')];
  const [head, ...body] = rows.map(pad);
  return [`| ${head.map(mdCell).join(' | ')} |`, `|${' --- |'.repeat(width)}`, ...body.map((r) => `| ${r.map(mdCell).join(' | ')} |`)].join('\n');
}

function irToMarkdown(ir) {
  return (
    ir
      .map((b) => {
        if (b.type === 'heading') return `${'#'.repeat(b.level || 1)} ${b.text}`;
        if (b.type === 'list') return b.items.map((it, i) => (b.ordered ? `${i + 1}. ${it}` : `- ${it}`)).join('\n');
        if (b.type === 'table') return mdTable(b.rows);
        return b.text;
      })
      .join('\n\n') + '\n'
  );
}

function irToText(ir) {
  return ir
    .map((b) => {
      if (b.type === 'list') return b.items.map((it, i) => (b.ordered ? `${i + 1}. ${it}` : `• ${it}`)).join('\n');
      if (b.type === 'table') return b.rows.map((r) => r.join('\t')).join('\n');
      return b.text;
    })
    .join('\n\n');
}

function tablesFromIr(ir) {
  return ir.filter((b) => b.type === 'table' && b.rows.length);
}

module.exports = { irFromHtml, irFromText, irFromSlides, irFromSheets, irFromAi, irToMarkdown, irToText, tablesFromIr, mdTable };
