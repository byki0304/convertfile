import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'conversion_list.dart';

/// "최근 변환 기록": the latest conversions of every format, with a download button when done.
class RecentConversionsPanel extends ConsumerStatefulWidget {
  const RecentConversionsPanel({super.key, this.limit = 5});

  final int limit;

  @override
  ConsumerState<RecentConversionsPanel> createState() => _RecentConversionsPanelState();
}

class _RecentConversionsPanelState extends ConsumerState<RecentConversionsPanel> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  List<Conversion>? _items;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen(String uid) {
    _sub?.cancel();
    _uid = uid;
    _sub = Api.conversions(uid)
        .orderBy('createdAt', descending: true)
        .limit(widget.limit)
        .snapshots()
        .listen((s) => _apply([for (final d in s.docs) Conversion(d.id, d.data())]), onError: (_) => _apply(const []));
  }

  void _apply(List<Conversion> all) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _items = all.where((c) => !c.expiredAt(now)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final uid = ref.watch(uidProvider);
    if (uid != null && uid != _uid) _listen(uid);
    final items = _items;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.s('최근 변환 기록', 'Recent conversions', '最近の変換履歴'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (uid != null && items == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items == null || items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Foldy(pose: FoldyPose.point, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.s('아직 변환한 파일이 없어요.', 'No conversions yet.', 'まだ変換したファイルがありません。'),
                      style: const TextStyle(color: AppColors.sub),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final (i, c) in items.indexed) ...[if (i > 0) const Divider(height: 18), _row(c)],
        ],
      ),
    );
  }

  Widget _row(Conversion c) {
    final t = ref.read(textProvider);
    final status = jobStatusOf(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.outputName ?? c.sourceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FormatPill(c.target.label, ext: c.target.ext),
            StatusPill(status),
            if (status == JobStatus.done)
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)),
                onPressed: () => downloadConversion(context, ref, c.id),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(t.s('내려받기', 'Download', 'ダウンロード')),
              ),
          ],
        ),
      ],
    );
  }
}
