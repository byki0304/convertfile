import 'dart:typed_data';

import '../file_rules.dart';

/// A file chosen by the user. [blob] is the browser File, uploaded as-is without reading it into memory.
class PickedFile {
  PickedFile({required this.name, required this.size, required this.blob, required this.readBytes});

  final String name;
  final int size;
  final Object blob;
  final Future<Uint8List> Function() readBytes;

  String get ext => extOf(name);
}

class PdfInfo {
  const PdfInfo({required this.pages, required this.encrypted, required this.error});

  final int pages;
  final bool encrypted;
  final String error;

  bool get ok => error.isEmpty;
}
