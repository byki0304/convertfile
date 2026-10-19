import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../../shared/app_text.dart';
import '../../shared/errors.dart';
import '../../shared/file_rules.dart';
import '../../shared/logic/frame.dart';
import '../../shared/logic/pdf_logic.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/web/bridge.dart';
import '../../shared/widgets.dart';

class EditDoc {
  EditDoc(this.name, this.bytes, this.model);

  final String name;
  final Uint8List bytes;
  final PdfEditModel model;
}

class EditNotifier extends Notifier<EditDoc?> {
  @override
  EditDoc? build() => null;

  void open(String name, Uint8List bytes, int pages) => state = EditDoc(name, bytes, PdfEditModel(pages));

  void close() => state = null;

  void update(void Function(PdfEditModel m) change) {
    final d = state;
    if (d == null) return;
    final m = d.model.copy();
    change(m);
    state = EditDoc(d.name, d.bytes, m);
  }

  /// After saving, the saved order becomes the new baseline.
  void markSaved(Uint8List bytes) {
    final d = state;
    if (d == null) return;
    state = EditDoc(d.name, bytes, PdfEditModel(d.model.pages.length));
  }
}

final editStateProvider = NotifierProvider<EditNotifier, EditDoc?>(EditNotifier.new);

/// Menu 10. Page grid editing in the browser (up to 500 pages).
class PdfEditPage extends ConsumerStatefulWidget {
  const PdfEditPage({super.key});

  @override
  ConsumerState<PdfEditPage> createState() => _PdfEditPageState();
}

class _PdfEditPageState extends ConsumerState<PdfEditPage> {
  bool _busy = false;
  String? _message;
  bool _messageError = false;
  late final NavNotifier _nav;

  @override
  void initState() {
    super.initState();
    _nav = ref.read(navProvider.notifier);
    _nav.leaveGuard = _confirmLeave;
    setDropHandler(this, (files) => files.isEmpty ? null : _openFile(files.first));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final h = ref.read(pdfHandoffProvider);
      if (h == null || h.tab != PdfTab.edit) return;
      ref.read(pdfHandoffProvider.notifier).set(null);
      if (h.file != null) await _openFile(h.file!);
      if (h.bytes != null) await _openBytes(h.name ?? 'document.pdf', h.bytes!);
    });
  }

  @override
  void dispose() {
    if (_nav.leaveGuard == _confirmLeave) _nav.leaveGuard = null;
    setDropHandler(this, null);
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    final d = ref.read(editStateProvider);
    if (d == null || !d.model.dirty || !mounted) return true;
    final t = ref.read(textProvider);
    final ok = await confirmDialog(
      context,
      t,
      t.s('저장하지 않은 변경이 있습니다. 나가시겠습니까?', 'You have unsaved changes. Leave anyway?', '保存していない変更があります。移動しますか?'),
      confirmLabel: t.s('나가기', 'Leave', '移動する'),
      danger: true,
    );
    if (ok) ref.read(editStateProvider.notifier).close();
    return ok;
  }

  void _say(String? m, {bool error = false}) => setState(() {
    _message = m;
    _messageError = error;
  });

  Future<void> _openFile(PickedFile f) async {
    final t = ref.read(textProvider);
    final guest = ref.read(isGuestProvider);
    if (f.ext != 'pdf') return _say(pdfOnly(t), error: true);
    final check = checkPdfToolSize(f.size, guest: guest);
    if (check == PdfSizeCheck.tooLarge) return _say(pdfToolTooLarge(t, guest), error: true);
    if (!await _confirmLeave()) return;
    setState(() => _busy = true);
    final bytes = await f.readBytes();
    await _openBytes(f.name, bytes);
    if (check == PdfSizeCheck.warn) _say(pdfToolWarn(t));
  }

  Future<void> _openBytes(String name, Uint8List bytes) async {
    final t = ref.read(textProvider);
    setState(() => _busy = true);
    final info = await pdfInfo(bytes);
    setState(() => _busy = false);
    if (!info.ok) return _say(info.encrypted ? encryptedFile(t) : genericError(t), error: true);
    if (info.pages > Limits.editMaxPages) {
      return _say(t.s('500페이지까지 편집할 수 있습니다.', 'You can edit up to 500 pages.', '500ページまで編集できます。'), error: true);
    }
    ref.read(editStateProvider.notifier).open(name, bytes, info.pages);
    _say(null);
  }

  Future<void> _pick() async {
    final files = await pickFiles(accept: '.pdf,application/pdf');
    if (files.isNotEmpty) await _openFile(files.first);
  }

  Future<Uint8List?> _build(List<int> pages) async {
    final d = ref.read(editStateProvider);
    if (d == null || pages.isEmpty) return null;
    setState(() => _busy = true);
    try {
      return await pdfPick(d.bytes, pages);
    } catch (_) {
      _say(genericError(ref.read(textProvider)), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final d = ref.read(editStateProvider)!;
    final out = await _build(d.model.pages);
    if (out == null) return;
    downloadBytes(out, '${baseNameOf(d.name)}_edited.pdf', 'application/pdf');
    ref.read(editStateProvider.notifier).markSaved(out);
    final t = ref.read(textProvider);
    _say(t.s('PDF를 만들었습니다. 내려받기를 시작합니다.', 'PDF created. Starting the download.', 'PDFを作成しました。ダウンロードを開始します。'));
  }

  Future<void> _saveSelected() async {
    final d = ref.read(editStateProvider)!;
    final out = await _build(d.model.selectedInOrder);
    if (out == null) return;
    downloadBytes(out, '${baseNameOf(d.name)}_pages.pdf', 'application/pdf');
  }

  Future<void> _printSelected() async {
    final d = ref.read(editStateProvider)!;
    final out = await _build(d.model.selectedInOrder);
    if (out == null) return;
    await Printing.layoutPdf(onLayout: (_) async => out, name: '${baseNameOf(d.name)}_pages.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final d = ref.watch(editStateProvider);
    final phone = frameOf(MediaQuery.sizeOf(context)) != AppFrame.desktop;
    final n = ref.read(editStateProvider.notifier);
    final m = d?.model;
    final hasSel = (m?.selected.isNotEmpty ?? false);
    return PageBody(
      child: PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              d?.name ?? t.s('PDF 편집', 'Edit PDF', 'PDF編集'),
              trailing: OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: Text(t.s('파일 열기', 'Open file', 'ファイルを開く')),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_message!, style: TextStyle(color: _messageError ? AppColors.danger : AppColors.ok)),
              ),
            if (d == null || m == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: UploadDropZone(
                  onTap: _busy ? null : _pick,
                  caption: t.s('편집할 PDF 파일 하나를 올려 주세요.', 'Upload one PDF file to edit.', '編集するPDFファイルを1つアップロードしてください。'),
                ),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(label: Text(t.selectAll), selected: m.allSelected, onSelected: (v) => n.update((x) => x.selectAll(v))),
                  OutlinedButton(
                    onPressed: hasSel && !_busy ? () => n.update((x) => x.deleteSelected()) : null,
                    child: Text(t.s('선택 삭제', 'Delete selected', '選択削除')),
                  ),
                  OutlinedButton(
                    onPressed: hasSel && !_busy ? _saveSelected : null,
                    child: Text(t.s('선택 페이지만 저장', 'Save selected pages', '選択ページのみ保存')),
                  ),
                  OutlinedButton(
                    onPressed: hasSel && !_busy ? _printSelected : null,
                    child: Text(t.s('선택 페이지만 인쇄', 'Print selected pages', '選択ページのみ印刷')),
                  ),
                  OutlinedButton(
                    onPressed: m.canUndo && !_busy ? () => n.update((x) => x.undo()) : null,
                    child: Text(t.s('되돌리기', 'Undo', '元に戻す')),
                  ),
                  FilledButton(onPressed: m.pages.isEmpty || _busy ? null : _save, child: Text(t.s('저장', 'Save', '保存'))),
                ],
              ),
              const SizedBox(height: 12),
              PdfDocumentViewBuilder(
                documentRef: PdfDocumentRefData(d.bytes, sourceName: 'edit_${d.name}_${d.bytes.length}'),
                builder: (context, doc) => _grid(context, doc, m, phone ? 100.0 : 140.0, phone),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, PdfDocument? doc, PdfEditModel m, double thumb, bool phone) {
    final t = ref.read(textProvider);
    final n = ref.read(editStateProvider.notifier);
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / (thumb + 12)).floor().clamp(1, 20);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var pos = 0; pos < m.pages.length; pos++)
              SizedBox(
                key: ValueKey('p${m.pages[pos]}'),
                width: w,
                child: DragTarget<int>(
                  onWillAcceptWithDetails: (det) => det.data != pos,
                  onAcceptWithDetails: (det) => n.update((x) => x.move(det.data, pos)),
                  builder: (context, cand, _) {
                    final cell = _cell(t, doc, m, pos, w, highlight: cand.isNotEmpty);
                    final feedback = Material(
                      color: Colors.transparent,
                      child: Transform.scale(
                        scale: 1.03,
                        child: SizedBox(width: w, child: _cell(t, doc, m, pos, w, lifted: true)),
                      ),
                    );
                    return phone
                        ? LongPressDraggable<int>(
                            data: pos,
                            feedback: feedback,
                            childWhenDragging: Opacity(opacity: 0.3, child: cell),
                            child: cell,
                          )
                        : Draggable<int>(
                            data: pos,
                            feedback: feedback,
                            childWhenDragging: Opacity(opacity: 0.3, child: cell),
                            child: cell,
                          );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(AppText t, PdfDocument? doc, PdfEditModel m, int pos, double w, {bool highlight = false, bool lifted = false}) {
    final src = m.pages[pos];
    final checked = m.selected.contains(src);
    return Container(
      decoration: cardDecoration(color: highlight ? AppColors.aiBubble : AppColors.paper, lifted: lifted),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / 1.414,
            child: doc == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : PdfPageView(document: doc, pageNumber: src + 1, maximumDpi: 72),
          ),
          Row(
            children: [
              Semantics(
                label: '${t.select} ${pos + 1}',
                child: Checkbox(value: checked, onChanged: (_) => ref.read(editStateProvider.notifier).update((x) => x.toggle(src))),
              ),
              Expanded(
                child: Text('${pos + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
