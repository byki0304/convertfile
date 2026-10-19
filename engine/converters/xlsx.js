'use strict';
// Tables → XLSX. Numeric strings become numbers. Max 20 sheets, 5000 rows per sheet.

const ExcelJS = require('exceljs');

const MAX_SHEETS = 20;
const MAX_ROWS = 5000;

function toNumber(s) {
  const t = String(s ?? '').trim();
  if (!/^[-+]?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?%?$/.test(t)) return null;
  if (/^0\d/.test(t.replace(/^[-+]/, ''))) return null;
  const pct = t.endsWith('%');
  const n = Number(t.replace(/[,%]/g, ''));
  if (!Number.isFinite(n)) return null;
  return pct ? n / 100 : n;
}

function safeSheetName(name, used) {
  let base = String(name || 'Sheet').replace(/[\\/?*[\]:]/g, ' ').trim().slice(0, 28) || 'Sheet';
  let n = base;
  let i = 2;
  while (used.has(n.toLowerCase())) n = `${base} ${i++}`;
  used.add(n.toLowerCase());
  return n;
}

/** tables: [{sheetName?, rows: string[][]}] */
async function tablesToXlsx(tables) {
  const wb = new ExcelJS.Workbook();
  const used = new Set();
  tables.slice(0, MAX_SHEETS).forEach((t, idx) => {
    const ws = wb.addWorksheet(safeSheetName(t.sheetName || `Table ${idx + 1}`, used));
    for (const r of t.rows.slice(0, MAX_ROWS)) {
      ws.addRow(r.map((c) => toNumber(c) ?? String(c ?? '')));
    }
    if (t.rows.length) ws.getRow(1).font = { bold: true };
    ws.columns.forEach((col) => {
      let w = 8;
      col.eachCell({ includeEmpty: false }, (cell) => (w = Math.max(w, Math.min(60, String(cell.value ?? '').length + 2))));
      col.width = w;
    });
  });
  return Buffer.from(await wb.xlsx.writeBuffer());
}

/** Tab- or comma-separated text tables. */
function tablesFromDelimited(text) {
  const lines = String(text || '').replace(/\r\n?/g, '\n').split('\n');
  const tables = [];
  let cur = null;
  let delim = null;
  const flush = () => {
    if (cur && cur.length >= 2) tables.push({ rows: cur });
    cur = null;
    delim = null;
  };
  for (const line of lines) {
    const d = line.includes('\t') ? '\t' : line.split(',').length >= 2 ? ',' : null;
    if (!d || (delim && d !== delim)) {
      flush();
      if (!d) continue;
    }
    delim = d;
    (cur ||= []).push(d === ',' ? parseCsvLine(line) : line.split('\t').map((s) => s.trim()));
  }
  flush();
  return tables;
}

function parseCsvLine(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) {
      if (ch === '"' && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else if (ch === '"') q = false;
      else cur += ch;
    } else if (ch === '"') q = true;
    else if (ch === ',') {
      out.push(cur.trim());
      cur = '';
    } else cur += ch;
  }
  out.push(cur.trim());
  return out;
}

module.exports = { tablesToXlsx, tablesFromDelimited, toNumber, MAX_SHEETS, MAX_ROWS };
