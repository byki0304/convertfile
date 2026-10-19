import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api.dart';
import '../../shared/state.dart';
import '../../shared/widgets.dart';
import 'conversion_list.dart';

/// Shows `'{파일명}' 변환을 마쳤습니다. [내려받기]` when a job finishes while another menu is open.
class ConversionDoneWatcher extends ConsumerStatefulWidget {
  const ConversionDoneWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConversionDoneWatcher> createState() => _ConversionDoneWatcherState();
}

class _ConversionDoneWatcherState extends ConsumerState<ConversionDoneWatcher> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  final Map<String, String> _last = {};

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen(String uid) {
    _sub?.cancel();
    _uid = uid;
    _last.clear();
    var first = true;
    _sub = Api.conversions(uid).orderBy('createdAt', descending: true).limit(20).snapshots().listen((s) {
      for (final d in s.docs) {
        final c = Conversion(d.id, d.data());
        final prev = _last[c.id];
        _last[c.id] = c.isDone ? 'done' : c.status;
        if (first || prev == null || prev == 'done' || !c.isDone) continue;
        final nav = ref.read(navProvider);
        final here = !nav.myPage && nav.group == MenuGroup.convert && nav.convertTab == c.target;
        if (here || !mounted) continue;
        final t = ref.read(textProvider);
        final name = c.sourceName;
        showSnack(
          context,
          t.s("'$name' 변환을 마쳤습니다.", "'$name' has been converted.", "'$name'の変換が完了しました。"),
          actionLabel: t.s('내려받기', 'Download', 'ダウンロード'),
          onAction: () => downloadConversion(context, ref, c.id),
        );
      }
      first = false;
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(uidProvider);
    if (uid != null && uid != _uid) _listen(uid);
    return widget.child;
  }
}
