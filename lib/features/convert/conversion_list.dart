import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api.dart';
import '../../shared/app_text.dart';
import '../../shared/errors.dart';
import '../../shared/file_rules.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/web/bridge.dart';
import '../../shared/widgets.dart';

/// A local row shown while the file is still uploading (before the server creates the job).
class PendingUpload {
  PendingUpload(this.key, this.name, this.size, this.target);

  final String key;
  final String name;
  final int size;
  final TargetFormat target;
  int progress = 0;
  String? errorCode;
}

String modeLabel(AppText t, String mode) => switch (mode) {
  'layout' => t.s('레이아웃 유지', 'Keep layout', 'レイアウト維持'),
  'table' => t.s('표 추출', 'Extract tables', '表の抽出'),
  _ => t.s('내용 중심', 'Content first', '内容重視'),
};

Future<void> downloadConversion(BuildContext context, WidgetRef ref, String conversionId) async {
  final t = ref.read(textProvider);
  try {
    final r = await Api.call('getDownloadUrl', {'conversionId': conversionId});
    openDownload(r['url'] as String);
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, errorMessage(t, e.code, guest: ref.read(isGuestProvider)));
  }
}

JobStatus jobStatusOf(Conversion c) => switch (c.status) {
  'done' => c.isDone ? JobStatus.done : JobStatus.running,
  'failed' => JobStatus.failed,
  'running' => JobStatus.running,
  _ => JobStatus.queued,
};

/// Recent conversions (10 per page). [target] null lists every format (my page).
class ConversionList extends ConsumerStatefulWidget {
  const ConversionList({super.key, this.target, this.pending = const [], required this.emptyText});

  final TargetFormat? target;
  final List<PendingUpload> pending;
  final String emptyText;

  @override
  ConsumerState<ConversionList> createState() => _ConversionListState();
}

class _ConversionListState extends ConsumerState<ConversionList> {
  int _limit = 10;
  final Set<String> _checked = {};
  final Set<String> _expanded = {};
  final Set<String> _summarizing = {};
  bool _deleting = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Conversion>? _items;
  bool _hasMore = false;
  String? _uid;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _listen(String uid) {
    _sub?.cancel();
    _uid = uid;
    Query<Map<String, dynamic>> q = Api.conversions(uid);
    if (widget.target != null) q = q.where('targetFormat', isEqualTo: widget.target!.ext);
    q = q.orderBy('createdAt', descending: true).limit(_limit + 1);
    _sub = q.snapshots().listen((s) {
      ref.read(backupModeProvider.notifier).set(false);
      _apply([for (final d in s.docs) Conversion(d.id, d.data())]);
    }, onError: (_) => _loadBackup());
  }

  Future<void> _loadBackup() async {
    ref.read(backupModeProvider.notifier).set(true);
    try {
      final r = await Api.call('readBackup', {'collection': 'conversions'});
      final docs = (r['docs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map));
      var list = [for (final d in docs) Conversion(d['id'] as String, d)];
      if (widget.target != null) list = list.where((c) => c.target == widget.target).toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      _apply(list.take(_limit + 1).toList());
    } catch (_) {
      _apply(const []);
    }
  }

  void _apply(List<Conversion> all) {
    if (!mounted) return;
    final now = DateTime.now();
    final visible = all.where((c) => !c.expiredAt(now)).toList();
    setState(() {
      _hasMore = visible.length > _limit;
      _items = visible.take(_limit).toList();
      final ids = _items!.map((c) => c.id).toSet();
      _checked.retainAll(ids);
      _expanded.retainAll(ids);
    });
  }

  Future<void> _delete() async {
    final t = ref.read(textProvider);
    final items = _items ?? const [];
    final running = items.where((c) => _checked.contains(c.id) && c.isRunning).toList();
    if (running.isNotEmpty) {
      showSnack(context, t.runningCannotDelete);
      return;
    }
    if (!await confirmDialog(context, t, t.deleteConfirm(_checked.length), confirmLabel: t.delete, danger: true)) return;
    setState(() => _deleting = true);
    try {
      await Api.call('deleteByIds', {'conversionIds': _checked.toList()});
      setState(_checked.clear);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(t, e.code));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _summarize(Conversion c) async {
    final t = ref.read(textProvider);
    setState(() => _summarizing.add(c.id));
    try {
      await Api.call('summarizeConversion', {'conversionId': c.id, 'lang': ref.read(langProvider).code});
      setState(() => _expanded.add(c.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(t, e.code, guest: ref.read(isGuestProvider)));
    } finally {
      if (mounted) setState(() => _summarizing.remove(c.id));
    }
  }

  Future<void> _openInEditor(Conversion c) async {
    final t = ref.read(textProvider);
    try {
      final r = await Api.call('getDownloadUrl', {'conversionId': c.id});
      final bytes = await fetchBytes(r['url'] as String);
      ref.read(pdfHandoffProvider.notifier).set(PdfHandoff(tab: PdfTab.edit, bytes: bytes, name: c.outputName));
      await ref.read(navProvider.notifier).pdf(PdfTab.edit);
    } catch (e) {
      if (mounted) showSnack(context, e is ApiException ? errorMessage(t, e.code) : genericError(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final uid = ref.watch(uidProvider);
    if (uid != null && uid != _uid) _listen(uid);
    final items = _items;
    final pending = widget.pending;
    final backup = ref.watch(backupModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          t.s('최근 변환 기록', 'Recent conversions', '最近の変換履歴'),
          trailing: (items?.isNotEmpty ?? false) && !backup
              ? SelectionToggleButton(
                  selectedCount: _checked.length,
                  busy: _deleting,
                  onSelectAll: () => setState(() => _checked.addAll(items!.map((c) => c.id))),
                  onDelete: _delete,
                )
              : null,
        ),
        for (final p in pending) _pendingRow(t, p),
        if (items == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty && pending.isEmpty)
          EmptyState(widget.emptyText)
        else
          for (final c in items) _row(t, c, backup),
        if (_hasMore)
          Center(
            child: TextButton(
              onPressed: () {
                _limit += 10;
                if (_uid != null) _listen(_uid!);
              },
              child: Text(t.s('더 보기', 'Show more', 'もっと見る')),
            ),
          ),
      ],
    );
  }

  Widget _pendingRow(AppText t, PendingUpload p) {
    final failed = p.errorCode != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(color: failed ? AppColors.errorCard : AppColors.paper),
      child: Row(
        children: [
          FormatCard(p.target.ext, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${extOf(p.name).toUpperCase()} → ${p.target.ext.toUpperCase()} · ${t.size(p.size)}',
                  style: const TextStyle(color: AppColors.sub, fontSize: 13),
                ),
                if (failed)
                  Text(
                    errorMessage(t, p.errorCode, guest: ref.read(isGuestProvider), target: p.target),
                    style: const TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
          ),
          StatusPill(failed ? JobStatus.failed : JobStatus.uploading, progress: p.progress),
        ],
      ),
    );
  }

  Widget _row(AppText t, Conversion c, bool backup) {
    final now = DateTime.now();
    final status = jobStatusOf(c);
    final expanded = _expanded.contains(c.id);
    final h = c.hoursLeft(now);
    return ExpandableRow(
      key: ValueKey(c.id),
      expanded: expanded,
      color: status == JobStatus.failed ? AppColors.errorCard : AppColors.paper,
      onToggle: () => setState(() => expanded ? _expanded.remove(c.id) : _expanded.add(c.id)),
      checked: backup ? null : _checked.contains(c.id),
      onChecked: (v) => setState(() => v ? _checked.add(c.id) : _checked.remove(c.id)),
      header: Row(
        children: [
          FormatCard(c.target.ext, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${c.sourceExt.toUpperCase()} → ${c.target.ext.toUpperCase()}',
                      style: const TextStyle(color: AppColors.sub, fontSize: 13),
                    ),
                    StatusPill(status),
                    Text(t.size(c.isDone ? c.outputSize! : c.sourceSize), style: const TextStyle(color: AppColors.sub, fontSize: 13)),
                    Text(t.s('$h시간 후 삭제', 'Deleted in ${h}h', '$h時間後に削除'), style: const TextStyle(color: AppColors.sub, fontSize: 13)),
                  ],
                ),
                if (c.isDone && !backup)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => downloadConversion(context, ref, c.id),
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(t.s('내려받기', 'Download', 'ダウンロード')),
                      ),
                      TextButton.icon(
                        onPressed: _summarizing.contains(c.id) ? null : () => _summarize(c),
                        icon: _summarizing.contains(c.id)
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.short_text, size: 18),
                        label: Text(t.s('3줄 요약', '3-line summary', '3行要約')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(c.sourceName),
          const SizedBox(height: 4),
          Text('${t.s('방식', 'Method', '方式')}: ${modeLabel(t, c.mode)}'),
          if (c.pageCount != null) Text('${t.s('페이지 수', 'Pages', 'ページ数')}: ${t.number(c.pageCount!)}'),
          if (c.isDone)
            Text(
              t.s('변환을 마쳤습니다. 7일 동안 내려받을 수 있습니다.', 'Conversion finished. You can download it for 7 days.', '変換が完了しました。7日間ダウンロードできます。'),
              style: const TextStyle(color: AppColors.ok),
            ),
          if (c.summaryLines.isNotEmpty) ...[const SizedBox(height: 6), for (final l in c.summaryLines) Text('• $l')],
          if (status == JobStatus.failed)
            Text(
              errorMessage(t, c.errorCode, guest: ref.read(isGuestProvider), target: c.target, ext: c.sourceExt),
              style: const TextStyle(color: AppColors.danger),
            ),
          if (c.fontSubstituted)
            Text(
              t.s('일부 글꼴을 무료 글꼴로 바꿔 표시했습니다.', 'Some fonts were replaced with free fonts.', '一部のフォントを無料フォントに置き換えて表示しました。'),
              style: const TextStyle(color: AppColors.sub),
            ),
          if (c.isDone && c.target == TargetFormat.pdf && !backup)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: () => _openInEditor(c),
                icon: const Icon(Icons.edit_document, size: 18),
                label: Text(t.s('PDF 편집으로 열기', 'Open in PDF editor', 'PDF編集で開く')),
              ),
            ),
        ],
      ),
    );
  }
}
