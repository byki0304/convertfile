import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

@JS('cfPickFiles')
external JSPromise<web.FileList?> _pickFiles(String accept, bool multiple);

@JS('cfSetDropHandler')
external void _setDropHandler(JSFunction? fn);

@JS('cfDownloadBytes')
external void _downloadBytes(JSUint8Array bytes, String name, String mime);

@JS('cfOpenDownload')
external void _openDownload(String url);

@JS('cfSpeechSupported')
external bool _speechSupported();

@JS('cfSpeechStart')
external bool _speechStart(String lang, JSFunction onText, JSFunction onEnd);

@JS('cfSpeechStop')
external void _speechStop();

extension type _PdfInfoJs(JSObject _) implements JSObject {
  external int get pages;
  external bool get encrypted;
  external String get error;
}

@JS('cfPdfInfo')
external JSPromise<_PdfInfoJs> _pdfInfo(JSUint8Array bytes);

@JS('cfPdfMerge')
external JSPromise<JSUint8Array> _pdfMerge(JSArray<JSUint8Array> list);

@JS('cfPdfPick')
external JSPromise<JSUint8Array> _pdfPick(JSUint8Array bytes, JSArray<JSNumber> indices);

PickedFile _wrap(web.File f) =>
    PickedFile(name: f.name, size: f.size, blob: f, readBytes: () async => (await f.arrayBuffer().toDart).toDart.asUint8List());

List<PickedFile> _list(web.FileList? list) {
  if (list == null) return const [];
  return [for (var i = 0; i < list.length; i++) _wrap(list.item(i)!)];
}

Future<List<PickedFile>> pickFiles({required String accept, bool multiple = false}) async =>
    _list(await _pickFiles(accept, multiple).toDart);

void setDropHandler(void Function(List<PickedFile> files)? handler) {
  _setDropHandler(handler == null ? null : ((web.FileList list) => handler(_list(list))).toJS);
}

void downloadBytes(Uint8List bytes, String name, String mime) => _downloadBytes(bytes.toJS, name, mime);

void openDownload(String url) => _openDownload(url);

bool speechSupported() => _speechSupported();

bool speechStart(String lang, void Function(String text) onText, void Function() onEnd) =>
    _speechStart(lang, ((JSString t) => onText(t.toDart)).toJS, onEnd.toJS);

void speechStop() => _speechStop();

Future<PdfInfo> pdfInfo(Uint8List bytes) async {
  final r = await _pdfInfo(bytes.toJS).toDart;
  return PdfInfo(pages: r.pages, encrypted: r.encrypted, error: r.error);
}

Future<Uint8List> pdfMerge(List<Uint8List> files) async => (await _pdfMerge([for (final f in files) f.toJS].toJS).toDart).toDart;

Future<Uint8List> pdfPick(Uint8List bytes, List<int> pageIndices) async =>
    (await _pdfPick(bytes.toJS, [for (final i in pageIndices) i.toJS].toJS).toDart).toDart;

void reloadPage() => web.window.location.reload();

/// Reads a signed URL (bucket CORS must allow the app origin).
Future<Uint8List> fetchBytes(String url) async {
  final res = await web.window.fetch(url.toJS).toDart;
  if (!res.ok) throw StateError('http ${res.status}');
  return (await res.arrayBuffer().toDart).toDart.asUint8List();
}
