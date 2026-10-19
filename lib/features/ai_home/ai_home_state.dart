import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/web/bridge.dart';

@immutable
class AiDraft {
  const AiDraft({this.text = '', this.file, this.isVoice = false});

  final String text;
  final PickedFile? file;
  final bool isVoice;
}

/// Home input kept in Riverpod so it survives frame changes and menu switches.
class AiDraftNotifier extends Notifier<AiDraft> {
  @override
  AiDraft build() => const AiDraft();

  void setText(String v, {bool? voice}) => state = AiDraft(text: v, file: state.file, isVoice: voice ?? state.isVoice);

  void setFile(PickedFile? f) => state = AiDraft(text: state.text, file: f, isVoice: state.isVoice);

  void clear() => state = const AiDraft();
}

final aiDraftProvider = NotifierProvider<AiDraftNotifier, AiDraft>(AiDraftNotifier.new);

/// Files attached to turns in this session, so [메뉴로 이동] can carry them. Lost on reload by design.
class TurnFilesNotifier extends Notifier<Map<String, PickedFile>> {
  @override
  Map<String, PickedFile> build() => const {};

  void put(String turnId, PickedFile f) => state = {...state, turnId: f};
}

final turnFilesProvider = NotifierProvider<TurnFilesNotifier, Map<String, PickedFile>>(TurnFilesNotifier.new);
