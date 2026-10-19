'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const JSZip = require('jszip');
const ExcelJS = require('exceljs');

const ir = require('../converters/docir');
const { irToDocx, setDocxFont } = require('../converters/docx');
const { tablesToXlsx, tablesFromDelimited, toNumber, MAX_SHEETS } = require('../converters/xlsx');
const { slidesToPptx, sheetsToPptx } = require('../converters/pptx');
const { irToHwpx, sectionXml, headerXml } = require('../converters/hwpx');
const { convertFile, mdHtml } = require('../converters');
const { checkHwpx } = require('../converters/inspect');

const FIXTURES = path.join(__dirname, 'fixtures');
const tmpDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'cf-engine-'));
const noAi = { key: '', model: '', count: async () => assert.fail('AI must not be called') };

test('shared lib files are identical copies of functions/lib', () => {
  for (const f of ['file_rules.js', 'gemini.js', 'text_extract.js']) {
    const a = fs.readFileSync(path.join(__dirname, '..', 'lib', f), 'utf8');
    const b = fs.readFileSync(path.join(__dirname, '..', '..', 'functions', 'lib', f), 'utf8');
    assert.equal(a, b, `${f} differs; copy functions/lib/${f} to engine/lib/`);
  }
});

test('IR from markdown keeps headings, lists and tables', () => {
  const md = fs.readFileSync(path.join(FIXTURES, 'sample.md'), 'utf8');
  const blocks = ir.irFromHtml(mdHtml(md));
  assert.deepEqual(blocks[0], { type: 'heading', level: 1, text: '분기 보고서' });
  assert.ok(blocks.some((b) => b.type === 'list' && b.items.includes('매출 증가')));
  const table = blocks.find((b) => b.type === 'table');
  assert.deepEqual(table.rows[0], ['항목', '금액']);
  assert.deepEqual(table.rows[2], ['비용', '800']);
});

test('IR round trip to markdown and text', () => {
  const blocks = [
    { type: 'heading', level: 2, text: '제목' },
    { type: 'paragraph', text: '본문 | 파이프' },
    { type: 'list', ordered: true, items: ['하나', '둘'] },
    { type: 'table', rows: [['a', 'b'], ['1']] },
  ];
  const md = ir.irToMarkdown(blocks);
  assert.match(md, /^## 제목/);
  assert.match(md, /1\. 하나\n2\. 둘/);
  assert.match(md, /\| a \| b \|\n\| --- \| --- \|\n\| 1 \|  \|/);
  assert.match(ir.irToText(blocks), /a\tb\n1/);
});

test('irFromText splits paragraphs on blank lines', () => {
  assert.deepEqual(ir.irFromText('첫 줄\r\n이어짐\r\n\r\n둘째'), [
    { type: 'paragraph', text: '첫 줄\n이어짐' },
    { type: 'paragraph', text: '둘째' },
  ]);
});

test('irFromAi clamps levels and drops empty blocks', () => {
  const out = ir.irFromAi([
    { type: 'heading', level: 9, text: ' 큰 제목 ' },
    { type: 'list', items: ['', 'x'] },
    { type: 'paragraph', text: '' },
    { type: 'table', rows: [] },
  ]);
  assert.deepEqual(out, [
    { type: 'heading', level: 6, text: '큰 제목' },
    { type: 'list', ordered: false, items: ['x'] },
  ]);
});

test('toNumber parses only plain numeric cells', () => {
  assert.equal(toNumber('1,234'), 1234);
  assert.equal(toNumber('-3.5'), -3.5);
  assert.equal(toNumber('15%'), 0.15);
  assert.equal(toNumber('010-1234'), null);
  assert.equal(toNumber('0012'), null);
  assert.equal(toNumber('12,34'), null);
  assert.equal(toNumber('abc'), null);
  assert.equal(toNumber(''), null);
});

test('tablesFromDelimited reads tab and quoted CSV blocks', () => {
  const tables = tablesFromDelimited('이름\t수량\n사과\t3\n\n설명 문장\n\na,"b, c"\n1,"say ""hi"""\n');
  assert.equal(tables.length, 2);
  assert.deepEqual(tables[0].rows, [['이름', '수량'], ['사과', '3']]);
  assert.deepEqual(tables[1].rows, [['a', 'b, c'], ['1', 'say "hi"']]);
});

test('tablesToXlsx writes numbers, safe unique sheet names and the sheet cap', async () => {
  const tables = Array.from({ length: MAX_SHEETS + 2 }, () => ({ sheetName: 'A/B', rows: [['h'], ['1,000']] }));
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(await tablesToXlsx(tables));
  assert.equal(wb.worksheets.length, MAX_SHEETS);
  assert.equal(wb.worksheets[0].name, 'A B');
  assert.equal(wb.worksheets[1].name, 'A B 2');
  assert.equal(wb.worksheets[0].getCell('A2').value, 1000);
});

test('irToDocx writes a DOCX with the 맑은 고딕 font name', async () => {
  const buf = await irToDocx([
    { type: 'heading', level: 1, text: '제목' },
    { type: 'table', rows: [['a', 'b'], ['1', '2']] },
  ]);
  const zip = await JSZip.loadAsync(buf);
  const doc = await zip.file('word/document.xml').async('string');
  assert.match(doc, /제목/);
  assert.match(doc, /<w:tbl>/);
  assert.match(doc, /맑은 고딕/);
});

test('setDocxFont rewrites the default run font', async () => {
  const zip = new JSZip();
  zip.file('word/styles.xml', '<w:styles><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Cambria"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>');
  const out = await JSZip.loadAsync(await setDocxFont(await zip.generateAsync({ type: 'nodebuffer' })));
  const xml = await out.file('word/styles.xml').async('string');
  assert.match(xml, /w:eastAsia="맑은 고딕"/);
  assert.doesNotMatch(xml, /Cambria/);
});

test('slidesToPptx and sheetsToPptx produce slides', async () => {
  const deck = await JSZip.loadAsync(await slidesToPptx([{ title: '첫 장', bullets: ['a', 'b'], notes: 'n' }, { title: '둘째', bullets: [] }]));
  assert.ok(deck.file('ppt/slides/slide2.xml'));
  const rows = [['h1', 'h2'], ...Array.from({ length: 20 }, (_, i) => [`r${i}`, String(i)])];
  const sheets = await JSZip.loadAsync(await sheetsToPptx([{ name: '표', rows }]));
  const s2 = await sheets.file('ppt/slides/slide2.xml').async('string');
  assert.match(s2, /표 \(2\/2\)/);
  assert.match(s2, /h1/);
});

test('HWPX package layout, fonts and well-formed section', async () => {
  const blocks = [
    { type: 'table', rows: [['가', '나'], ['1', '<2>']] },
    { type: 'heading', level: 1, text: '제목 & 부제' },
    { type: 'paragraph', text: '첫 줄\n둘째 줄' },
  ];
  const buf = await irToHwpx(blocks, '문서');
  await checkHwpx(buf);
  const zip = await JSZip.loadAsync(buf);
  const names = Object.keys(zip.files);
  assert.equal(names[0], 'mimetype');
  assert.equal(await zip.file('mimetype').async('string'), 'application/hwp+zip');
  for (const f of ['version.xml', 'META-INF/container.xml', 'META-INF/manifest.xml', 'Contents/content.hpf', 'Contents/header.xml', 'Contents/section0.xml', 'settings.xml']) {
    assert.ok(zip.file(f), `missing ${f}`);
  }
  const header = headerXml();
  assert.match(header, /face="함초롬바탕"/);
  assert.match(header, /face="함초롬돋움"/);
  assert.doesNotMatch(header, /\{\{/);
  const sec = sectionXml(blocks);
  assert.equal((sec.match(/<hp:secPr /g) || []).length, 1, 'exactly one secPr, even when the document starts with a table');
  assert.match(sec, /^<\?xml[^>]*\?><hs:sec[^>]*><hp:p [^>]*><hp:run charPrIDRef="0"><hp:secPr /);
  assert.match(sec, /&lt;2&gt;/);
  assert.match(sec, /제목 &amp; 부제/);
  assert.match(sec, /<hp:lineBreak\/>/);
  const ids = [...sec.matchAll(/<hp:p id="(\d+)"/g)].map((m) => m[1]);
  assert.equal(new Set(ids).size, ids.length, 'paragraph ids are unique');
  assert.equal((await zip.file('Contents/content.hpf').async('string')).includes('문서'), true);
});

test('convertFile: md → hwpx, md → txt, txt → xlsx without LibreOffice or AI', async () => {
  const dir = tmpDir();
  try {
    const md = path.join(FIXTURES, 'sample.md');
    const hwpx = await convertFile({ srcPath: md, ext: 'md', target: 'hwpx', workDir: dir, ai: noAi, title: 'sample' });
    await checkHwpx(fs.readFileSync(hwpx.outPath));
    assert.equal(hwpx.fontSubstituted, false);

    const txt = await convertFile({ srcPath: md, ext: 'md', target: 'txt', workDir: dir, ai: noAi });
    assert.match(fs.readFileSync(txt.outPath, 'utf8'), /\r\n/);

    const csv = path.join(FIXTURES, 'table.txt');
    const xlsx = await convertFile({ srcPath: csv, ext: 'txt', target: 'xlsx', workDir: dir, ai: noAi });
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.readFile(xlsx.outPath);
    assert.equal(wb.worksheets[0].getCell('B2').value, 1200);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('convertFile rejects same-format and unsupported pairs', async () => {
  const dir = tmpDir();
  try {
    const md = path.join(FIXTURES, 'sample.md');
    await assert.rejects(convertFile({ srcPath: md, ext: 'md', target: 'md', workDir: dir, ai: noAi }), { code: 'same-format' });
    await assert.rejects(convertFile({ srcPath: md, ext: 'zip', target: 'pdf', workDir: dir, ai: noAi }), { code: 'unsupported-format' });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('txt without tables fails with no-table-found', async () => {
  const dir = tmpDir();
  try {
    const p = path.join(dir, 'plain.txt');
    fs.writeFileSync(p, '표가 없는 문장입니다.');
    await assert.rejects(convertFile({ srcPath: p, ext: 'txt', target: 'xlsx', workDir: dir, ai: noAi }), { code: 'no-table-found' });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
