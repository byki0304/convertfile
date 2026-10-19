'use strict';
const test = require('node:test');
const assert = require('node:assert');
const rules = require('../lib/file_rules');
const { decodeText } = require('../lib/text_extract');

test('format table', () => {
  assert.equal(rules.checkFormat('pdf', 'hwp'), 'ok');
  assert.equal(rules.checkFormat('pptx', 'xlsx'), 'ok');
  assert.equal(rules.checkFormat('hwpx', 'hwt'), 'same-format');
  assert.equal(rules.checkFormat('docx', 'doc'), 'same-format');
  assert.equal(rules.checkFormat('pdf', 'docm'), 'unsupported-format');
  assert.equal(rules.checkFormat('exe', 'pdf'), 'unsupported-format');
});

test('limits', () => {
  assert.equal(rules.fileLimit(false), 1073741824);
  assert.equal(rules.fileLimit(true), 104857600);
  assert.equal(rules.aiLimit(false), 200);
  assert.equal(rules.aiLimit(true), 30);
});

test('magic bytes', () => {
  const ole = Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
  const zip = Buffer.from([0x50, 0x4b, 0x03, 0x04, 0, 0]);
  assert.equal(rules.checkMagic('pdf', Buffer.from('%PDF-1.7')), 'ok');
  assert.equal(rules.checkMagic('pdf', zip), 'unsupported-format');
  assert.equal(rules.checkMagic('docx', zip), 'ok');
  assert.equal(rules.checkMagic('docx', ole), 'encrypted-file');
  assert.equal(rules.checkMagic('hwp', ole), 'ok');
  assert.equal(rules.checkMagic('txt', Buffer.from('안녕하세요', 'utf8')), 'ok');
  assert.equal(rules.checkMagic('txt', zip), 'unsupported-format');
});

test('needs AI and mode', () => {
  assert.equal(rules.needsAi('md', 'pdf'), true);
  assert.equal(rules.needsAi('pptx', 'xls'), false);
  assert.equal(rules.needsAi('txt', 'pdf'), false);
  assert.equal(rules.modeOf('docx', 'txt'), 'layout');
  assert.equal(rules.engineOf('docx', 'md'), 'pandoc');
});

test('content disposition keeps Korean names', () => {
  const h = rules.contentDisposition('보고서.pdf');
  assert.match(h, /filename\*=UTF-8''%EB%B3%B4%EA%B3%A0%EC%84%9C\.pdf/);
});

test('text decoding: utf-8, BOM, euc-kr', () => {
  assert.equal(decodeText(Buffer.from('한글 text', 'utf8')), '한글 text');
  assert.equal(decodeText(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('가', 'utf8')])), '가');
  assert.equal(decodeText(Buffer.from([0xc7, 0xd1, 0xb1, 0xdb])), '한글');
});
