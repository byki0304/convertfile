import '../file_rules.dart';

/// Page order of an opened PDF. Values are zero-based indices into the source file.
class PdfEditModel {
  PdfEditModel(int pageCount) : pages = List.generate(pageCount, (i) => i), selected = {}, _undo = [];

  PdfEditModel._(this.pages, this.selected, this._undo);

  final List<int> pages;
  final Set<int> selected;
  final List<List<int>> _undo;

  bool get canUndo => _undo.isNotEmpty;
  bool get dirty => _undo.isNotEmpty;
  bool get allSelected => pages.isNotEmpty && selected.length == pages.length;

  /// Selected source indices, in current page order.
  List<int> get selectedInOrder => [
    for (final p in pages)
      if (selected.contains(p)) p,
  ];

  void toggle(int sourceIndex) => selected.contains(sourceIndex) ? selected.remove(sourceIndex) : selected.add(sourceIndex);

  void selectAll(bool value) {
    selected.clear();
    if (value) selected.addAll(pages);
  }

  void move(int from, int to) {
    if (from == to || from < 0 || from >= pages.length) return;
    _undo.add(List.of(pages));
    final p = pages.removeAt(from);
    pages.insert(to.clamp(0, pages.length), p);
  }

  void deleteSelected() {
    if (selected.isEmpty) return;
    _undo.add(List.of(pages));
    pages.removeWhere(selected.contains);
    selected.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final prev = _undo.removeLast();
    pages
      ..clear()
      ..addAll(prev);
    selected.removeWhere((p) => !pages.contains(p));
  }

  PdfEditModel copy() => PdfEditModel._(List.of(pages), {...selected}, [for (final u in _undo) List.of(u)]);
}

/// Ordered merge slots. Shows 5 slots and grows by 5 up to 20.
class MergeSlots<T> {
  MergeSlots() : slots = List.filled(Limits.mergeSlotsStep, null, growable: true);

  MergeSlots.from(List<T?> current) : slots = List.of(current, growable: true);

  final List<T?> slots;

  int get visible => slots.length;
  bool get canGrow => slots.length < Limits.mergeSlotsMax;
  List<T> get filled => [for (final s in slots) ?s];

  void grow() {
    if (!canGrow) return;
    slots.addAll(List.filled(Limits.mergeSlotsStep, null));
  }

  /// Puts items into the first empty slots from top to bottom. Returns how many did not fit.
  int addAll(Iterable<T> items) {
    var left = 0;
    for (final item in items) {
      var i = slots.indexOf(null);
      if (i < 0 && canGrow) {
        grow();
        i = slots.indexOf(null);
      }
      if (i < 0) {
        left++;
        continue;
      }
      slots[i] = item;
    }
    return left;
  }

  void removeAt(int i) => slots[i] = null;

  void move(int from, int to) {
    if (from == to) return;
    final item = slots.removeAt(from);
    slots.insert(to.clamp(0, slots.length), item);
  }

  void clear() {
    slots
      ..clear()
      ..addAll(List.filled(Limits.mergeSlotsStep, null));
  }
}

enum PdfSizeCheck { ok, warn, tooLarge }

PdfSizeCheck checkPdfToolSize(int totalBytes, {required bool guest}) {
  if (totalBytes > Limits.pdfToolBytes(guest)) return PdfSizeCheck.tooLarge;
  if (totalBytes > Limits.pdfWarnBytes) return PdfSizeCheck.warn;
  return PdfSizeCheck.ok;
}

String mergedFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'merged_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
}
