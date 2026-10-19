import 'package:flutter/material.dart';

import 'theme.dart';

/// Conversion result formats (menus 2~8). Mirrors functions/file_rules.js and engine/file_rules.js.
enum TargetFormat {
  md('md', 'Markdown'),
  pdf('pdf', 'PDF'),
  docx('docx', 'Word'),
  pptx('pptx', 'PowerPoint'),
  xlsx('xlsx', 'Excel'),
  hwpx('hwpx', '한글'),
  txt('txt', 'TXT');

  const TargetFormat(this.ext, this.label);

  final String ext;
  final String label;

  static TargetFormat? fromExt(String? ext) => TargetFormat.values.where((f) => f.ext == ext).firstOrNull;
}

enum ConvertMode { layout, content, table }

class Limits {
  static const loginFileBytes = 1073741824;
  static const guestFileBytes = 104857600;
  static const loginAiCalls = 200;
  static const guestAiCalls = 30;
  static const pdfWarnBytes = 300 * 1024 * 1024;
  static const mergeSlotsStep = 5;
  static const mergeSlotsMax = 20;
  static const editMaxPages = 500;
  static const retentionHours = 168;

  static int fileBytes(bool guest) => guest ? guestFileBytes : loginFileBytes;
  static int dailyBytes(bool guest) => guest ? guestFileBytes : loginFileBytes;
  static int pdfToolBytes(bool guest) => guest ? guestFileBytes : loginFileBytes;
  static int aiCalls(bool guest) => guest ? guestAiCalls : loginAiCalls;
}

const Map<TargetFormat, List<String>> acceptedInputs = {
  TargetFormat.md: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  TargetFormat.pdf: ['md', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  TargetFormat.docx: ['md', 'pdf', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  TargetFormat.pptx: ['md', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'],
  TargetFormat.xlsx: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'hwp', 'hwpx', 'hwt', 'txt'],
  TargetFormat.hwpx: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt'],
  TargetFormat.txt: ['md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt'],
};

const knownExts = {'md', 'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'hwp', 'hwpx', 'hwt', 'txt'};

/// Family used for same-format detection.
const Map<String, String> extFamily = {
  'md': 'md',
  'pdf': 'pdf',
  'doc': 'docx',
  'docx': 'docx',
  'ppt': 'pptx',
  'pptx': 'pptx',
  'xls': 'xlsx',
  'xlsx': 'xlsx',
  'hwp': 'hwpx',
  'hwpx': 'hwpx',
  'hwt': 'hwpx',
  'txt': 'txt',
};

String extOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  if (i < 0 || i == fileName.length - 1) return '';
  return fileName.substring(i + 1).toLowerCase();
}

String baseNameOf(String fileName) {
  final i = fileName.lastIndexOf('.');
  return i <= 0 ? fileName : fileName.substring(0, i);
}

enum RuleResult { ok, unsupported, sameFormat }

RuleResult checkFormat(TargetFormat target, String ext) {
  final e = ext.toLowerCase();
  if (extFamily[e] == target.ext) return RuleResult.sameFormat;
  if (!acceptedInputs[target]!.contains(e)) return RuleResult.unsupported;
  return RuleResult.ok;
}

ConvertMode modeOf(TargetFormat target, String ext) => switch (target) {
  TargetFormat.pdf => ConvertMode.layout,
  TargetFormat.xlsx => ConvertMode.table,
  TargetFormat.docx when const {'hwp', 'hwpx', 'hwt', 'txt'}.contains(ext) => ConvertMode.layout,
  _ => ConvertMode.content,
};

/// Whether the conversion needs AI before it starts (OCR is decided by the engine).
bool needsAi(TargetFormat target, String ext) {
  if (target == TargetFormat.pptx) return ext != 'xls' && ext != 'xlsx';
  if (ext == 'pdf') return const {TargetFormat.md, TargetFormat.docx, TargetFormat.xlsx}.contains(target);
  return false;
}

String outputNameOf(String sourceName, TargetFormat target) => '${baseNameOf(sourceName)}.${target.ext}';

Color formatColor(String ext) => switch (extFamily[ext.toLowerCase()] ?? ext.toLowerCase()) {
  'md' => AppColors.md,
  'pdf' => AppColors.pdf,
  'docx' => AppColors.docx,
  'pptx' => AppColors.pptx,
  'xlsx' => AppColors.xlsx,
  'hwpx' => AppColors.hwpx,
  'txt' => AppColors.txt,
  _ => AppColors.calc,
};

/// MIME types accepted by storage.rules for uploads.
const Map<String, String> uploadContentTypes = {
  'md': 'text/markdown',
  'txt': 'text/plain',
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'hwp': 'application/x-hwp',
  'hwt': 'application/x-hwp',
  'hwpx': 'application/hwp+zip',
};
