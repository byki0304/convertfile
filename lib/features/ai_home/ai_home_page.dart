import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api.dart';
import '../../shared/app_text.dart';
import '../../shared/errors.dart';
import '../../shared/file_rules.dart';
import '../../shared/logic/frame.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/web/bridge.dart';
import '../../shared/widgets.dart';
import '../convert/recent_panel.dart';
import 'ai_home_state.dart';
import 'route_card.dart';

String speechLang(AppLang l) => switch (l) {
  AppLang.ko => 'ko-KR',
  AppLang.en => 'en-US',
  AppLang.ja => 'ja-JP',
};

/// Menu 1. Input card, presets, and the conversation list.
class AiHomePage extends ConsumerStatefulWidget {
  const AiHomePage({super.key});

  @override
  ConsumerState<AiHomePage> createState() => _AiHomePageState();
}

class _AiHomePageState extends ConsumerState<AiHomePage> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  bool _sending = false;
  bool _listening = false;
  int? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(aiDraftProvider).text);
    setDropHandler(this, (files) {
      if (files.isNotEmpty) _attach(files.first);
    });
  }

  @override
  void dispose() {
    setDropHandler(this, null);
    if (_listening) speechStop();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _attach(PickedFile f) {
    final t = ref.read(textProvider);
    final guest = ref.read(isGuestProvider);
    if (!knownExts.contains(f.ext)) {
      setState(() => _error = unsupportedFormat(t, knownExts.toList()));
      return;
    }
    if (f.size > Limits.fileBytes(guest)) {
      setState(() => _error = fileTooLarge(t, guest));
      return;
    }
    ref.read(aiDraftProvider.notifier).setFile(f);
    setState(() => _error = null);
  }

  Future<bool> _pick() async {
    final files = await pickFiles(accept: knownExts.map((e) => '.$e').join(','));
    if (files.isEmpty) return false;
    _attach(files.first);
    return ref.read(aiDraftProvider).file != null;
  }

  void _toggleVoice() {
    if (_listening) {
      speechStop();
      return;
    }
    final ok = speechStart(speechLang(ref.read(langProvider)), (s) {
      _text.text = s;
      ref.read(aiDraftProvider.notifier).setText(s, voice: true);
    }, () => mounted ? setState(() => _listening = false) : null);
    setState(() => _listening = ok);
  }

  Future<void> _send() async {
    final t = ref.read(textProvider);
    final draft = ref.read(aiDraftProvider);
    final text = _text.text.trim();
    if (_sending) return;
    if (text.isEmpty && draft.file == null) {
      setState(() => _error = t.s('내용을 입력하거나 파일을 선택해 주세요.', 'Enter a message or choose a file.', '内容を入力するか、ファイルを選択してください。'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _progress = null;
    });
    try {
      final data = <String, dynamic>{'text': text, 'isVoice': draft.isVoice, 'lang': ref.read(langProvider).code};
      final file = draft.file;
      if (file != null) {
        final uid = ref.read(uidProvider)!;
        final task = Api.upload(uid, file);
        final sub = task.snapshotEvents.listen((s) {
          if (s.totalBytes > 0 && mounted) setState(() => _progress = (s.bytesTransferred * 100 / s.totalBytes).floor());
        }, onError: (_) {});
        try {
          final snap = await task;
          data['filePath'] = snap.ref.fullPath;
          data['fileName'] = file.name;
        } finally {
          await sub.cancel();
        }
      }
      final r = await Api.call('submitPrompt', data);
      final turnId = r['turnId'] as String?;
      if (turnId != null && file != null) ref.read(turnFilesProvider.notifier).put(turnId, file);
      _text.clear();
      ref.read(aiDraftProvider.notifier).clear();
    } on ApiException catch (e) {
      setState(() => _error = errorMessage(t, e.code, guest: ref.read(isGuestProvider)));
    } catch (_) {
      setState(() => _error = genericError(t));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _preset(String text, {bool needsFile = true}) async {
    if (needsFile && ref.read(aiDraftProvider).file == null && !await _pick()) return;
    _text.text = text;
    ref.read(aiDraftProvider.notifier).setText(text, voice: false);
    await _send();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _header(AppText t, AppFrame frame) {
    final hint = t.s(
      '"이 한글 파일 PDF로 바꿔줘"처럼 말하거나 파일을 넣어 보세요. 알맞은 메뉴로 안내합니다.',
      'Say something like "Convert this Hangul file to PDF" or add a file. We will guide you to the right menu.',
      '「このハングルファイルをPDFに変換して」のように話すか、ファイルを入れてください。適切なメニューへご案内します。',
    );
    final title = Text(
      t.groupHome,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.ink),
    );
    if (frame == AppFrame.phonePortrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Foldy(pose: FoldyPose.wave, size: 56),
          const SizedBox(width: 8),
          Expanded(
            child: SpeechBubble(
              child: Text(hint, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 10),
              SpeechBubble(
                tailRight: true,
                child: Text(hint, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Foldy(pose: FoldyPose.wave, size: 104),
      ],
    );
  }

  Widget _dropZone({required bool compact}) =>
      UploadDropZone(onTap: _sending ? null : _pick, compact: compact, caption: knownExts.map((e) => e.toUpperCase()).join(' · '));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final draft = ref.watch(aiDraftProvider);
    final frame = frameOf(MediaQuery.sizeOf(context));
    final desktop = frame == AppFrame.desktop;
    final landscape = frame == AppFrame.phoneLandscape;
    final hint = t.s(
      '변환할 형식이나 궁금한 것을 말하거나 파일을 넣으세요.',
      'Say the format you want, ask anything, or add a file.',
      '変換したい形式や知りたいことを話すか、ファイルを入れてください。',
    );
    final field = Focus(
      onKeyEvent: _onKey,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        minLines: 1,
        maxLines: desktop ? 4 : 2,
        maxLength: 4000,
        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
        onChanged: (v) => ref.read(aiDraftProvider.notifier).setText(v, voice: false),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
    final attachBtn = IconButton(
      tooltip: t.s('파일 첨부', 'Attach file', 'ファイル添付'),
      onPressed: _sending ? null : _pick,
      icon: const Icon(Icons.note_add_outlined),
    );
    final micBtn = speechSupported()
        ? IconButton(
            tooltip: t.s('음성 입력', 'Voice input', '音声入力'),
            onPressed: _sending ? null : _toggleVoice,
            icon: Icon(_listening ? Icons.mic : Icons.mic_none_rounded, color: _listening ? AppColors.danger : null),
          )
        : const SizedBox.shrink();
    final sendBtn = IconButton.filled(
      tooltip: t.s('실행', 'Send', '実行'),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        fixedSize: const Size(44, 44),
      ),
      onPressed: _sending ? null : _send,
      icon: _sending
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send_rounded, size: 20),
    );
    final input = PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: field),
              micBtn,
              attachBtn,
              const SizedBox(width: 4),
              sendBtn,
            ],
          ),
          if (draft.file != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FormatPill(
                  '${draft.file!.name} · ${t.size(draft.file!.size)}',
                  ext: draft.file!.ext,
                  trailing: Icons.close,
                  onTap: _sending ? null : () => ref.read(aiDraftProvider.notifier).setFile(null),
                ),
              ),
            ),
          if (_progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _progress! / 100),
            Text(t.uploading(_progress!), style: const TextStyle(fontSize: 12, color: AppColors.sub)),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
    );
    final toPdf = t.s('이 파일 PDF로 바꿔줘', 'Convert this file to PDF', 'このファイルをPDFに変換して');
    final summary = t.s('이 문서 3줄로 요약해줘', 'Summarize this document in 3 lines', 'この文書を3行で要約して');
    final presets = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PresetPill(label: toPdf, onTap: _sending ? null : () => _preset(toPdf)),
        PresetPill(label: summary, onTap: _sending ? null : () => _preset(summary)),
        PresetPill(
          label: t.s('100달러는 몇 원이야?', 'How many won is 100 dollars?', '100ドルは何ウォン?'),
          onTap: () {
            ref.read(calcHandoffProvider.notifier).set(const CalcHandoff(tab: CalcTab.fx, input: '100', currency: 'USD'));
            ref.read(navProvider.notifier).calc(CalcTab.fx);
          },
        ),
      ],
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!landscape) ...[_header(t, frame), const SizedBox(height: 14), _dropZone(compact: !desktop), const SizedBox(height: 12)],
        input,
        const SizedBox(height: 8),
        Text(t.aiNotice, style: const TextStyle(color: AppColors.sub, fontSize: 12)),
        const SizedBox(height: 12),
        presets,
        const SizedBox(height: 20),
        const TurnList(),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth >= 980;
        return PageBody(
          padding: EdgeInsets.fromLTRB(landscape ? 12 : 20, landscape ? 10 : 20, landscape ? 12 : 20, 20),
          maxWidth: side ? AppDims.contentMax + AppDims.recentPanel : AppDims.contentMax,
          child: side
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 20),
                    const SizedBox(width: AppDims.recentPanel, child: RecentConversionsPanel()),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [main, const SizedBox(height: 8), const RecentConversionsPanel(limit: 3)],
                ),
        );
      },
    );
  }
}

class TurnList extends ConsumerStatefulWidget {
  const TurnList({super.key});

  @override
  ConsumerState<TurnList> createState() => _TurnListState();
}

class _TurnListState extends ConsumerState<TurnList> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  List<Turn>? _turns;
  int _limit = 30;
  final Set<String> _checked = {};
  bool _deleting = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen(String uid) {
    _sub?.cancel();
    _uid = uid;
    _sub = Api.turns(uid).orderBy('createdAt', descending: true).limit(_limit).snapshots().listen((s) {
      ref.read(backupModeProvider.notifier).set(false);
      _apply([for (final d in s.docs) Turn(d.id, d.data())]);
    }, onError: (_) => _loadBackup());
  }

  Future<void> _loadBackup() async {
    ref.read(backupModeProvider.notifier).set(true);
    try {
      final r = await Api.call('readBackup', {'collection': 'turns'});
      final docs = (r['docs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map));
      final list = [for (final d in docs) Turn(d['id'] as String, d)]
        ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      _apply(list);
    } catch (_) {
      _apply(const []);
    }
  }

  void _apply(List<Turn> all) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _turns = all.where((x) => !x.expiredAt(now) && !(x.userHidden && x.aiHidden)).toList();
      final keys = {
        for (final x in _turns!) ...['${x.id}:user', '${x.id}:ai'],
      };
      _checked.retainAll(keys);
    });
  }

  Future<void> _delete() async {
    final t = ref.read(textProvider);
    if (!await confirmDialog(context, t, t.deleteConfirm(_checked.length), confirmLabel: t.delete, danger: true)) return;
    setState(() => _deleting = true);
    try {
      final parts = [
        for (final k in _checked) {'turnId': k.split(':').first, 'part': k.split(':').last},
      ];
      await Api.call('hideTurnParts', {'parts': parts});
      setState(_checked.clear);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, errorMessage(t, e.code));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final uid = ref.watch(uidProvider);
    if (uid != null && uid != _uid) _listen(uid);
    final turns = _turns;
    final backup = ref.watch(backupModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          t.s('대화 & 안내', 'Chat & guidance', '会話と案内'),
          trailing: (turns?.isNotEmpty ?? false) && !backup
              ? SelectionToggleButton(
                  selectedCount: _checked.length,
                  busy: _deleting,
                  onSelectAll: () => setState(() {
                    for (final x in turns!) {
                      if (!x.userHidden) _checked.add('${x.id}:user');
                      if (!x.aiHidden) _checked.add('${x.id}:ai');
                    }
                  }),
                  onDelete: _delete,
                )
              : null,
        ),
        if (turns == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (turns.isEmpty)
          EmptyState(
            frameOf(MediaQuery.sizeOf(context)) == AppFrame.phoneLandscape
                ? t.s(
                    '"이 한글 파일 PDF로 바꿔줘"처럼 말하거나 파일을 넣어 보세요. 알맞은 메뉴로 안내합니다.',
                    'Say something like "Convert this Hangul file to PDF" or add a file. We will guide you to the right menu.',
                    '「このハングルファイルをPDFに変換して」のように話すか、ファイルを入れてください。適切なメニューへご案内します。',
                  )
                : t.s('대화와 안내가 여기에 쌓입니다.', 'Your chat and guidance will appear here.', '会話と案内がここに表示されます。'),
          )
        else ...[
          for (final x in turns) _turn(t, x, backup),
          if (turns.length >= _limit)
            Center(
              child: TextButton(
                onPressed: () {
                  _limit += 30;
                  if (_uid != null) _listen(_uid!);
                },
                child: Text(t.s('더 보기', 'Show more', 'もっと見る')),
              ),
            ),
        ],
      ],
    );
  }

  Widget _bubble({required String key, required Color color, required Widget child, required bool backup, required bool alignRight}) {
    final t = ref.read(textProvider);
    final bubble = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: cardDecoration(color: color),
        padding: const EdgeInsets.fromLTRB(4, 6, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!backup)
              Semantics(
                label: t.select,
                child: Checkbox(
                  value: _checked.contains(key),
                  onChanged: (v) => setState(() => v == true ? _checked.add(key) : _checked.remove(key)),
                ),
              )
            else
              const SizedBox(width: 10),
            Expanded(
              child: Padding(padding: const EdgeInsets.only(top: 10), child: child),
            ),
          ],
        ),
      ),
    );
    if (alignRight) return Align(alignment: Alignment.centerRight, child: bubble);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 6),
          child: Foldy(pose: FoldyPose.head, size: 34),
        ),
        Flexible(child: bubble),
      ],
    );
  }

  /// Grounding sources plus the Google search suggestions that Gemini used.
  Widget _sources(AppText t, Turn x) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (x.sources.isNotEmpty) ...[
          Text(
            t.s('출처', 'Sources', '出典'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.sub),
          ),
          for (final s in x.sources)
            InkWell(
              onTap: () => openLink(s.uri),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (x.searchQueries.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in x.searchQueries)
                ActionChip(
                  avatar: const Icon(Icons.search_rounded, size: 16),
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () => openLink('https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}'),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _turn(AppText t, Turn x, bool backup) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!x.userHidden)
            _bubble(
              key: '${x.id}:user',
              color: AppColors.paper,
              backup: backup,
              alignRight: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (x.userText.isNotEmpty)
                    Row(
                      children: [
                        if (x.isVoice)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.mic, size: 16, color: AppColors.sub),
                          ),
                        Expanded(child: SelectableText(x.userText)),
                      ],
                    ),
                  if (x.fileName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FormatPill(x.fileName!, ext: extOf(x.fileName!)),
                    ),
                ],
              ),
            ),
          if (!x.aiHidden)
            _bubble(
              key: '${x.id}:ai',
              color: AppColors.aiBubble,
              backup: backup,
              alignRight: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (x.aiText.isNotEmpty) SelectableText(x.aiText),
                  for (final l in x.summaryLines) Text('• $l'),
                  if (x.sources.isNotEmpty || x.searchQueries.isNotEmpty) _sources(t, x),
                  if (x.routeCard != null && !backup) RouteCard(turn: x),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
