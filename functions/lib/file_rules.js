'use strict';
// Format table shared by functions/ and engine/ (keep both copies identical; engine test checks this).
// Mirrors lib/shared/file_rules.dart.

const TARGETS = ['md', 'pdf', 'docx', 'pptx', 'xlsx', 'hwpx', 'txt'];

const ACCEPTED = {
  md: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  pdf: ['md', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  docx: ['md', 'pdf', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  pptx: ['md', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  xlsx: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'hwp', 'hwpx', 'hwt', 'txt'],
  hwpx: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt'],
  txt: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt'],
};

const KNOWN = ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'];

const FAMILY = {
  md: 'md', pdf: 'pdf', doc: 'docx', docx: 'docx', ppt: 'pptx', pptx: 'pptx',
  xls: 'xlsx', xlsx: 'xlsx', hwp: 'hwpx', hwpx: 'hwpx', hwt: 'hwpx', txt: 'txt',
};

const LIMITS = {
  loginFileBytes: 1073741824,
  guestFileBytes: 104857600,
  loginAiCalls: 200,
  guestAiCalls: 30,
  retentionHours: 168,
  summarySourceBytes: 200 * 1024 * 1024,
  aiChars: 30000,
};

const fileLimit = (guest) => (guest ? LIMITS.guestFileBytes : LIMITS.loginFileBytes);
const dailyLimit = fileLimit;
const aiLimit = (guest) => (guest ? LIMITS.guestAiCalls : LIMITS.loginAiCalls);

function extOf(name) {
  const i = String(name || '').lastIndexOf('.');
  if (i < 0 || i === name.length - 1) return '';
  return name.slice(i + 1).toLowerCase();
}

function baseNameOf(name) {
  const i = String(name).lastIndexOf('.');
  return i <= 0 ? name : name.slice(0, i);
}

/** 'ok' | 'unsupported-format' | 'same-format' */
function checkFormat(target, ext) {
  const e = String(ext || '').toLowerCase();
  if (!TARGETS.includes(target)) return 'unsupported-format';
  if (FAMILY[e] === target) return 'same-format';
  if (!ACCEPTED[target].includes(e)) return 'unsupported-format';
  return 'ok';
}

function modeOf(target, ext) {
  if (target === 'pdf') return 'layout';
  if (target === 'xlsx') return 'table';
  if (target === 'docx' && ['hwp', 'hwpx', 'hwt', 'txt'].includes(ext)) return 'layout';
  return 'content';
}

/** AI needed before the job starts (OCR is decided later by the engine). */
function needsAi(target, ext) {
  if (target === 'pptx') return ext !== 'xls' && ext !== 'xlsx';
  if (ext === 'pdf') return ['md', 'docx', 'xlsx'].includes(target);
  return false;
}

function engineOf(target, ext) {
  if (target === 'pdf') return 'libreoffice';
  if (target === 'docx' && ext === 'md') return 'pandoc';
  if (target === 'docx' && ['hwp', 'hwpx', 'hwt', 'txt'].includes(ext)) return 'libreoffice';
  if (needsAi(target, ext)) return 'gemini';
  return 'native';
}

const OLE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
const ZIP = [0x50, 0x4b, 0x03, 0x04];
const PDF = [0x25, 0x50, 0x44, 0x46];

const startsWith = (buf, sig) => sig.every((b, i) => buf[i] === b);

/** Checks the first bytes against the extension. 'ok' | 'encrypted-file' | 'unsupported-format' */
function checkMagic(ext, head) {
  const b = head || Buffer.alloc(0);
  const ole = startsWith(b, OLE);
  const zip = startsWith(b, ZIP);
  switch (ext) {
    case 'pdf':
      return startsWith(b, PDF) ? 'ok' : 'unsupported-format';
    case 'docx':
    case 'pptx':
    case 'xlsx':
      if (zip) return 'ok';
      return ole ? 'encrypted-file' : 'unsupported-format';
    case 'hwpx':
      return zip ? 'ok' : 'unsupported-format';
    case 'doc':
    case 'ppt':
    case 'xls':
    case 'hwp':
    case 'hwt':
      return ole ? 'ok' : 'unsupported-format';
    case 'md':
    case 'txt':
      if (ole || zip || startsWith(b, PDF) || (b.includes(0x00) && !isUtf16(b))) return 'unsupported-format';
      return 'ok';
    default:
      return 'unsupported-format';
  }
}

function isUtf16(b) {
  return (b[0] === 0xff && b[1] === 0xfe) || (b[0] === 0xfe && b[1] === 0xff);
}

const CONTENT_TYPES = {
  md: 'text/markdown; charset=utf-8',
  txt: 'text/plain; charset=utf-8',
  pdf: 'application/pdf',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  hwpx: 'application/hwp+zip',
};

/** RFC 5987 attachment header that keeps Korean file names. */
function contentDisposition(name) {
  const ascii = name.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
}

module.exports = {
  TARGETS, ACCEPTED, KNOWN, FAMILY, LIMITS, CONTENT_TYPES,
  fileLimit, dailyLimit, aiLimit, extOf, baseNameOf, checkFormat, modeOf, needsAi, engineOf, checkMagic, contentDisposition,
};
