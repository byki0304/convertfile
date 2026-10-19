import 'dart:typed_data';

import 'picked_file.dart';

Future<List<PickedFile>> pickFiles({required String accept, bool multiple = false}) async => const [];

void setDropHandler(Object owner, void Function(List<PickedFile> files)? handler) {}

void downloadBytes(Uint8List bytes, String name, String mime) {}

void openDownload(String url) {}

bool speechSupported() => false;

bool speechStart(String lang, void Function(String text) onText, void Function() onEnd) => false;

void speechStop() {}

Future<PdfInfo> pdfInfo(Uint8List bytes) async => const PdfInfo(pages: 0, encrypted: false, error: 'unsupported');

Future<Uint8List> pdfMerge(List<Uint8List> files) async => throw UnsupportedError('web only');

Future<Uint8List> pdfPick(Uint8List bytes, List<int> pageIndices) async => throw UnsupportedError('web only');

void reloadPage() {}

Future<Uint8List> fetchBytes(String url) async => throw UnsupportedError('web only');
