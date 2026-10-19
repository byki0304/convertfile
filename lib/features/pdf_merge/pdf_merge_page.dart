import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../shared/errors.dart';
import '../../shared/logic/frame.dart';
import '../../shared/logic/pdf_logic.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/web/bridge.dart';
import '../../shared/widgets.dart';

class MergeItem {
  MergeItem(this.name, this.size, this.bytes, this.pages);

  final String name;
  final int size;
  final Uint8List bytes;
  final int pages;
}

class MergeNotifier extends Notifier<List<MergeItem?>> {
  @override
  List<MergeItem?> build() => MergeSlots<MergeItem>().slots;

  MergeSlots<MergeItem> get _m => MergeSlots.from(state);

  int add(List<MergeItem> items) {
    final m = _m;
    final left = m.addAll(items);
    state = m.slots;
    return left;
  }

  void grow() => state = (_m..grow()).slots;
  void remove(int i) => state = (_m..removeAt(i)).slots;
  void move(int from, int to) => state = (_m..move(from, to)).slots;
  void clear() => state = MergeSlots<MergeItem>().slots;
}

final mergeStateProvider = NotifierProvider<MergeNotifier, List<MergeItem?>>(MergeNotifier.new);

/// Menu 9. Merges up to 20 PDFs in the browser; files are not sent to the server.
class PdfMergePage extends ConsumerStatefulWidget {
  const PdfMergePage({super.key});

  @override
  ConsumerState<PdfMergePage> createState() => _PdfMergePageState();
}

class _PdfMergePageState extends ConsumerState<PdfMergePage> {
  bool _busy = false;
  String? _message;
  bool _messageError = false;

  @override
  void initState() {
    super.initState();
    setDropHandler(this, _addFiles);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = ref.read(pdfHandoffProvider);
      if (h != null && h.tab == PdfTab.merge && h.file != null) {
        ref.read(pdfHandoffProvider.notifier).set(null);
        _addFiles([h.file!]);
      }
    });
  }

  @override
  void dispose() {
    setDropHandler(this, null);
    super.dispose();
  }

  void _say(String? m, {bool error = false}) => setState(() {
    _message = m;
    _messageError = error;
  });

  Future<void> _addFiles(List<PickedFile> files) async {
    final t = ref.read(textProvider);
    final guest = ref.read(isGuestProvider);
    final pdfs = files.where((f) => f.ext == 'pdf').toList();
    if (pdfs.length != files.length) _say(pdfOnly(t), error: true);
    if (pdfs.isEmpty) return;
    final current = ref.read(mergeStateProvider).whereType<MergeItem>().fold<int>(0, (s, e) => s + e.size);
    final total = current + pdfs.fold<int>(0, (s, f) => s + f.size);
    if (checkPdfToolSize(total, guest: guest) == PdfSizeCheck.tooLarge) return _say(pdfToolTooLarge(t, guest), error: true);
    setState(() => _busy = true);
    final items = <MergeItem>[];
    for (final f in pdfs) {
      final bytes = await f.readBytes();
      final info = await pdfInfo(bytes);
      if (!info.ok) {
        _say(info.encrypted ? encryptedFile(t) : genericError(t), error: true);
        continue;
      }
      items.add(MergeItem(f.name, f.size, bytes, info.pages));
    }
    final left = ref.read(mergeStateProvider.notifier).add(items);
    setState(() => _busy = false);
    if (left > 0) {
      _say(
        t.s('PDF 파일을 올려 주세요. 최대 20개까지 합칠 수 있습니다.', 'Upload PDF files. You can merge up to 20.', 'PDFファイルをアップロードしてください。最大20個まで結合できます。'),
        error: true,
      );
    } else if (checkPdfToolSize(total, guest: guest) == PdfSizeCheck.warn) {
      _say(pdfToolWarn(t));
    }
  }

  Future<void> _pick() async => _addFiles(await pickFiles(accept: '.pdf,application/pdf', multiple: true));

  Future<void> _merge() async {
    final t = ref.read(textProvider);
    final items = ref.read(mergeStateProvider).whereType<MergeItem>().toList();
    if (items.isEmpty) return;
    setState(() => _busy = true);
    try {
      final out = await pdfMerge([for (final i in items) i.bytes]);
      downloadBytes(out, mergedFileName(DateTime.now()), 'application/pdf');
      _say(t.s('PDF를 만들었습니다. 내려받기를 시작합니다.', 'PDF created. Starting the download.', 'PDFを作成しました。ダウンロードを開始します。'));
    } catch (_) {
      _say(genericError(t), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final slots = ref.watch(mergeStateProvider);
    final items = slots.whereType<MergeItem>().toList();
    final phone = frameOf(MediaQuery.sizeOf(context)) != AppFrame.desktop;
    final totalPages = items.fold<int>(0, (s, e) => s + e.pages);
    final totalSize = items.fold<int>(0, (s, e) => s + e.size);
    return PageBody(
      child: PaperCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              t.s('PDF 합치기', 'Merge PDFs', 'PDF結合'),
              trailing: OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.add),
                label: Text(t.s('파일 추가', 'Add files', 'ファイル追加')),
              ),
            ),
            if (items.isEmpty)
              EmptyState(
                t.s(
                  'PDF 파일을 올려 주세요. 최대 20개까지 합칠 수 있습니다.',
                  'Upload PDF files. You can merge up to 20.',
                  'PDFファイルをアップロードしてください。最大20個まで結合できます。',
                ),
              ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: slots.length,
              onReorderItem: (from, to) => ref.read(mergeStateProvider.notifier).move(from, to),
              proxyDecorator: (child, _, _) => Transform.scale(
                scale: 1.03,
                child: Material(color: Colors.transparent, elevation: 8, child: child),
              ),
              itemBuilder: (context, i) => _slot(context, i, slots[i], phone, slots.length),
            ),
            if (slots.length < 20)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref.read(mergeStateProvider.notifier).grow(),
                  icon: const Icon(Icons.add),
                  label: Text(t.s('5칸 더 보기', 'Show 5 more slots', 'さらに5枠表示')),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${t.s('합계', 'Total', '合計')}: ${t.s('${t.number(totalPages)}쪽', '${t.number(totalPages)} pages', '${t.number(totalPages)}ページ')} · ${t.size(totalSize)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_message!, style: TextStyle(color: _messageError ? AppColors.danger : AppColors.ok)),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || items.length < 2 ? null : _merge,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.merge_type),
              label: Text(t.s('합치기', 'Merge', '結合')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(BuildContext context, int i, MergeItem? item, bool phone, int count) {
    final t = ref.read(textProvider);
    final n = ref.read(mergeStateProvider.notifier);
    final content = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: item == null ? AppColors.bg : AppColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (item == null)
            Expanded(
              child: InkWell(
                onTap: _busy ? null : _pick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(t.s('PDF 선택', 'Choose PDF', 'PDFを選択'), style: const TextStyle(color: AppColors.sub)),
                ),
              ),
            )
          else ...[
            SizedBox(
              width: 40,
              height: 52,
              child: PdfDocumentViewBuilder(
                documentRef: PdfDocumentRefData(item.bytes, sourceName: 'merge_${item.name}_${item.size}'),
                builder: (context, doc) => PdfPageView(document: doc, pageNumber: 1, maximumDpi: 48),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${t.s('${item.pages}쪽', '${item.pages} pages', '${item.pages}ページ')} · ${t.size(item.size)}',
                    style: const TextStyle(color: AppColors.sub, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: t.moveUp,
              onPressed: i == 0 ? null : () => n.move(i, i - 1),
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
            IconButton(
              tooltip: t.moveDown,
              onPressed: i == count - 1 ? null : () => n.move(i, i + 1),
              icon: const Icon(Icons.arrow_downward, size: 18),
            ),
            IconButton(tooltip: t.delete, onPressed: () => n.remove(i), icon: const Icon(Icons.close, size: 18)),
            if (!phone)
              ReorderableDragStartListener(
                index: i,
                child: Semantics(
                  label: t.dragHandle,
                  child: const MouseRegion(cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator)),
                ),
              ),
          ],
        ],
      ),
    );
    final key = ValueKey(item ?? 'empty_$i');
    if (item != null && phone) return ReorderableDelayedDragStartListener(key: key, index: i, child: content);
    return KeyedSubtree(key: key, child: content);
  }
}
