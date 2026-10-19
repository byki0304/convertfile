'use strict';
// IR → HWPX (OWPML) from engine/templates/hwpx, packed with jszip. Font names only (함초롬바탕/함초롬돋움).

const fs = require('node:fs');
const path = require('node:path');
const JSZip = require('jszip');

const TPL = path.join(__dirname, '..', 'templates', 'hwpx');
const read = (f) => fs.readFileSync(path.join(TPL, f), 'utf8');

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const LANGS = ['HANGUL', 'LATIN', 'HANJA', 'JAPANESE', 'OTHER', 'SYMBOL', 'USER'];

function fontfaces() {
  return LANGS.map(
    (l) =>
      `<hh:fontface lang="${l}" fontCnt="2"><hh:font id="0" face="함초롬바탕" type="TTF" isEmbedded="0"/><hh:font id="1" face="함초롬돋움" type="TTF" isEmbedded="0"/></hh:fontface>`,
  ).join('\n');
}

const seven = (v) => `hangul="${v}" latin="${v}" hanja="${v}" japanese="${v}" other="${v}" symbol="${v}" user="${v}"`;

// 0 body, 1~3 headings (돋움, bold), 4 table text.
const CHAR = [
  { height: 1000, font: 0, bold: false },
  { height: 1600, font: 1, bold: true },
  { height: 1400, font: 1, bold: true },
  { height: 1200, font: 1, bold: true },
  { height: 950, font: 0, bold: false },
];

function charPrs() {
  return CHAR.map(
    (c, id) =>
      `<hh:charPr id="${id}" height="${c.height}" textColor="#000000" shadeColor="none" useFontSpace="0" useKerning="0" symMark="NONE" borderFillIDRef="1">` +
      `<hh:fontRef ${seven(c.font)}/><hh:ratio ${seven(100)}/><hh:spacing ${seven(0)}/><hh:relSz ${seven(100)}/><hh:offset ${seven(0)}/>` +
      (c.bold ? '<hh:bold/>' : '') +
      '<hh:underline type="NONE" shape="SOLID" color="#000000"/><hh:strikeout shape="NONE" color="#000000"/><hh:outline type="NONE"/>' +
      '<hh:shadow type="NONE" color="#B2B2B2" offsetX="10" offsetY="10"/></hh:charPr>',
  ).join('\n');
}

function paraPr(id, align, prev, next) {
  return (
    `<hh:paraPr id="${id}" tabPrIDRef="0" condense="0" fontLineHeight="0" snapToGrid="1" suppressLineNumbers="0" checked="0">` +
    `<hh:align horizontal="${align}" vertical="BASELINE"/><hh:heading type="NONE" idRef="0" level="0"/>` +
    '<hh:breakSetting breakLatinWord="KEEP_WORD" breakNonLatinWord="KEEP_WORD" widowOrphan="0" keepWithNext="0" keepLines="0" pageBreakBefore="0" lineWrap="BREAK"/>' +
    '<hh:autoSpacing eAsianEng="0" eAsianNum="0"/>' +
    `<hh:margin><hc:intent value="0" unit="HWPUNIT"/><hc:left value="0" unit="HWPUNIT"/><hc:right value="0" unit="HWPUNIT"/><hc:prev value="${prev}" unit="HWPUNIT"/><hc:next value="${next}" unit="HWPUNIT"/></hh:margin>` +
    '<hh:lineSpacing type="PERCENT" value="160" unit="HWPUNIT"/>' +
    '<hh:border borderFillIDRef="1" offsetLeft="0" offsetRight="0" offsetTop="0" offsetBottom="0" connect="0" ignoreMargin="0"/></hh:paraPr>'
  );
}

const SEC_PR =
  '<hp:secPr id="" textDirection="HORIZONTAL" spaceColumns="1134" tabStop="8000" tabStopVal="4000" tabStopUnit="HWPUNIT" outlineShapeIDRef="1" memoShapeIDRef="0" textVerticalWidthHead="0" masterPageCnt="0">' +
  '<hp:grid lineGrid="0" charGrid="0" wonggojiFormat="0"/><hp:startNum pageStartsOn="BOTH" page="0" pic="0" tbl="0" equation="0"/>' +
  '<hp:visibility hideFirstHeader="0" hideFirstFooter="0" hideFirstMasterPage="0" border="SHOW_ALL" fill="SHOW_ALL" hideFirstPageNum="0" hideFirstEmptyLine="0" showLineNumber="0"/>' +
  '<hp:lineNumberShape restartType="0" countBy="0" distance="0" startNumber="0"/>' +
  '<hp:pagePr landscape="WIDELY" width="59528" height="84186" gutterType="LEFT_ONLY"><hp:margin header="4252" footer="4252" gutter="0" left="8504" right="8504" top="5668" bottom="4252"/></hp:pagePr>' +
  '<hp:footNotePr><hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/><hp:noteLine length="-1" type="SOLID" width="0.12 mm" color="#000000"/><hp:noteSpacing betweenNotes="283" belowLine="567" aboveLine="850"/><hp:numbering type="CONTINUOUS" newNum="1"/><hp:placement place="EACH_COLUMN" beneathText="0"/></hp:footNotePr>' +
  '<hp:endNotePr><hp:autoNumFormat type="DIGIT" userChar="" prefixChar="" suffixChar=")" supscript="0"/><hp:noteLine length="14692344" type="SOLID" width="0.12 mm" color="#000000"/><hp:noteSpacing betweenNotes="0" belowLine="567" aboveLine="850"/><hp:numbering type="CONTINUOUS" newNum="1"/><hp:placement place="END_OF_DOCUMENT" beneathText="0"/></hp:endNotePr>' +
  '<hp:pageBorderFill type="BOTH" borderFillIDRef="1" textBorder="PAPER" headerInside="0" footerInside="0" fillArea="PAPER"><hp:offset left="1417" right="1417" top="1417" bottom="1417"/></hp:pageBorderFill>' +
  '</hp:secPr><hp:ctrl><hp:colPr id="" type="NEWSPAPER" layout="LEFT" colCount="1" sameSz="1" sameGap="0"/></hp:ctrl>';

const TEXT_WIDTH = 59528 - 8504 * 2;

class Builder {
  constructor() {
    this.pid = 0;
    this.tid = 1;
    this.parts = [];
  }

  para(text, charId = 0, paraId = 0, prefix = '') {
    const first = this.pid === 0;
    const id = this.pid++;
    const runs = String(text).split('\n').map((line) => `<hp:t>${esc(line)}</hp:t>`).join('<hp:lineBreak/>');
    const body = `<hp:run charPrIDRef="${charId}">${runs}</hp:run>`;
    return `<hp:p id="${id}" paraPrIDRef="${paraId}" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">${first ? `<hp:run charPrIDRef="0">${SEC_PR}</hp:run>` : ''}${prefix}${body}</hp:p>`;
  }

  table(rows) {
    const first = this.pid === 0;
    const id = this.pid++;
    const cols = Math.max(...rows.map((r) => r.length));
    const cw = Math.floor(TEXT_WIDTH / cols);
    const rh = 1600;
    const trs = rows
      .map(
        (r, ri) =>
          '<hp:tr>' +
          Array.from({ length: cols }, (_, ci) => {
            const id = this.pid++;
            return (
              `<hp:tc name="" header="${ri === 0 ? 1 : 0}" hasMargin="0" protect="0" editable="0" dirty="0" borderFillIDRef="2">` +
              `<hp:subList id="" textDirection="HORIZONTAL" lineWrap="BREAK" vertAlign="CENTER" linkListIDRef="0" linkListNextIDRef="0" textWidth="0" textHeight="0" hasTextRef="0" hasNumRef="0">` +
              `<hp:p id="${id}" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0"><hp:run charPrIDRef="4"><hp:t>${esc(r[ci] ?? '')}</hp:t></hp:run></hp:p></hp:subList>` +
              `<hp:cellAddr colAddr="${ci}" rowAddr="${ri}"/><hp:cellSpan colSpan="1" rowSpan="1"/><hp:cellSz width="${cw}" height="${rh}"/>` +
              '<hp:cellMargin left="510" right="510" top="141" bottom="141"/></hp:tc>'
            );
          }).join('') +
          '</hp:tr>',
      )
      .join('');
    const tbl =
      `<hp:tbl id="${this.tid++}" zOrder="0" numberingType="TABLE" textWrap="TOP_AND_BOTTOM" textFlow="BOTH_SIDES" lock="0" dropcapstyle="None" pageBreak="CELL" repeatHeader="1" rowCnt="${rows.length}" colCnt="${cols}" cellSpacing="0" borderFillIDRef="2" noAdjust="0">` +
      `<hp:sz width="${cw * cols}" widthRelTo="ABSOLUTE" height="${rh * rows.length}" heightRelTo="ABSOLUTE" protect="0"/>` +
      '<hp:pos treatAsChar="1" affectLSpacing="0" flowWithText="1" allowOverlap="0" holdAnchorAndSO="0" vertRelTo="PARA" horzRelTo="COLUMN" vertAlign="TOP" horzAlign="LEFT" vertOffset="0" horzOffset="0"/>' +
      '<hp:outMargin left="0" right="0" top="0" bottom="0"/><hp:inMargin left="510" right="510" top="141" bottom="141"/>' +
      `${trs}</hp:tbl>`;
    return `<hp:p id="${id}" paraPrIDRef="0" styleIDRef="0" pageBreak="0" columnBreak="0" merged="0">${first ? `<hp:run charPrIDRef="0">${SEC_PR}</hp:run>` : ''}<hp:run charPrIDRef="0">${tbl}<hp:t/></hp:run></hp:p>`;
  }
}

function sectionXml(ir) {
  const b = new Builder();
  const ps = [];
  for (const blk of ir) {
    if (blk.type === 'heading') ps.push(b.para(blk.text, Math.min(3, blk.level || 1), 1));
    else if (blk.type === 'list') blk.items.forEach((it, i) => ps.push(b.para(blk.ordered ? `${i + 1}. ${it}` : `• ${it}`)));
    else if (blk.type === 'table' && blk.rows.length) ps.push(b.table(blk.rows));
    else ps.push(b.para(blk.text));
  }
  if (!ps.length) ps.push(b.para(''));
  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>' +
    '<hs:sec xmlns:ha="http://www.hancom.co.kr/hwpml/2011/app" xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core" xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head">' +
    ps.join('') +
    '</hs:sec>'
  );
}

function headerXml() {
  return read('header.xml')
    .replace('{{FONTFACES}}', fontfaces())
    .replace('{{CHARPRS}}', charPrs())
    .replace('{{PARAPRS}}', [paraPr(0, 'JUSTIFY', 0, 0), paraPr(1, 'LEFT', 800, 400)].join('\n'));
}

async function irToHwpx(ir, title = '') {
  const zip = new JSZip();
  zip.file('mimetype', 'application/hwp+zip', { compression: 'STORE' });
  zip.file('version.xml', read('version.xml'));
  zip.file('META-INF/container.xml', read('container.xml'));
  zip.file('META-INF/manifest.xml', read('manifest.xml'));
  zip.file('Contents/content.hpf', read('content.hpf').replace('{{TITLE}}', esc(title)));
  zip.file('Contents/header.xml', headerXml());
  zip.file('Contents/section0.xml', sectionXml(ir));
  zip.file('settings.xml', read('settings.xml'));
  const preview = ir
    .map((x) => (x.type === 'list' ? x.items.join('\n') : x.type === 'table' ? x.rows.map((r) => r.join('\t')).join('\n') : x.text))
    .join('\n')
    .slice(0, 1024);
  zip.file('Preview/PrvText.txt', preview);
  return zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE', mimeType: 'application/hwp+zip' });
}

module.exports = { irToHwpx, sectionXml, headerXml };
