import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
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
import 'conversion_list.dart';

String convertTitle(AppText t, TargetFormat f) => switch (f) {
  TargetFormat.md => t.s('Markdown으로 변환', 'Convert to Markdown', 'Markdownに変換'),
  TargetFormat.pdf => t.s('PDF로 변환', 'Convert to PDF', 'PDFに変換'),
  TargetFormat.docx => t.s('Word로 변환', 'Convert to Word', 'Wordに変換'),
  TargetFormat.pptx => t.s('PowerPoint로 변환', 'Convert to PowerPoint', 'PowerPointに変換'),
  TargetFormat.xlsx => t.s('Excel로 변환', 'Convert to Excel', 'Excelに変換'),
  TargetFormat.hwpx => t.s('한글로 변환', 'Convert to Hangul', 'ハングルに変換'),
  TargetFormat.txt => t.s('텍스트로 변환', 'Convert to text', 'テキストに変換'),
};

/// Client-side pre-check; the server checks everything again.
String? precheckFile(AppText t, TargetFormat target, PickedFile f, {required bool guest}) {
  switch (checkFormat(target, f.ext)) {
    case RuleResult.sameFormat:
      return sameFormat(t, f.ext);
    case RuleResult.unsupported:
      return unsupportedFormat(t, acceptedInputs[target]!);
    case RuleResult.ok:
      break;
  }
  if (f.size > Limits.fileBytes(guest)) return fileTooLarge(t, guest);
  return null;
}

/// Uploads the file and asks the server to queue the conversion. Returns the conversion id.
Future<String> startConversion(
  WidgetRef ref,
  PickedFile file,
  TargetFormat target, {
  void Function(int percent)? onProgress,
  String? turnId,
}) async {
  final uid = ref.read(uidProvider)!;
  final guest = ref.read(isGuestProvider);
  final usage = await Api.usage(uid, seoulDay(DateTime.now())).get().then((d) => d.data(), onError: (_) => null);
  final used = (usage?['bytes'] as num?)?.toInt() ?? 0;
  if (used + file.size > Limits.dailyBytes(guest)) throw const ApiException('quota-exceeded');
  final task = Api.upload(uid, file);
  final sub = task.snapshotEvents.listen((s) {
    if (s.totalBytes > 0) onProgress?.call((s.bytesTransferred * 100 / s.totalBytes).floor());
  }, onError: (_) {});
  try {
    final snap = await task;
    final r = await Api.call('requestConversion', {'path': snap.ref.fullPath, 'name': file.name, 'target': target.ext, 'turnId': ?turnId});
    return r['conversionId'] as String;
  } on FirebaseException catch (e) {
    throw ApiException(e.code == 'unauthorized' ? 'file-too-large' : 'network');
  } finally {
    await sub.cancel();
  }
}

class ConvertPage extends ConsumerStatefulWidget {
  const ConvertPage({super.key, required this.target});

  final TargetFormat target;

  @override
  ConsumerState<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends ConsumerState<ConvertPage> {
  PickedFile? _file;
  String? _error;
  bool _starting = false;
  final List<PendingUpload> _pending = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = ref.read(convertHandoffProvider);
      if (h != null && h.target == widget.target) {
        ref.read(convertHandoffProvider.notifier).set(null);
        _select(h.file);
        if (h.autoStart && _error == null) _start();
      }
    });
    setDropHandler((files) {
      if (files.isNotEmpty) _select(files.first);
    });
  }

  @override
  void dispose() {
    setDropHandler(null);
    super.dispose();
  }

  void _select(PickedFile f) {
    final t = ref.read(textProvider);
    setState(() {
      _file = f;
      _error = precheckFile(t, widget.target, f, guest: ref.read(isGuestProvider));
      if (_error != null) _file = null;
    });
  }

  Future<void> _pick() async {
    final files = await pickFiles(accept: acceptedInputs[widget.target]!.map((e) => '.$e').join(','));
    if (files.isNotEmpty) _select(files.first);
  }

  Future<void> _start() async {
    final f = _file;
    if (f == null || _starting) return;
    final p = PendingUpload('${DateTime.now().microsecondsSinceEpoch}', f.name, f.size, widget.target);
    setState(() {
      _starting = true;
      _file = null;
      _pending.removeWhere((e) => e.errorCode != null);
      _pending.insert(0, p);
    });
    try {
      await startConversion(ref, f, widget.target, onProgress: (v) => mounted ? setState(() => p.progress = v) : null);
      if (mounted) setState(() => _pending.remove(p));
    } on ApiException catch (e) {
      if (mounted) setState(() => p.errorCode = e.code);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final target = widget.target;
    final file = _file;
    final desktop = frameOf(MediaQuery.sizeOf(context)) == AppFrame.desktop;
    final upload = PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FormatCard(target.ext, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(convertTitle(t, target), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final e in acceptedInputs[target]!) FormatPill(e.toUpperCase(), ext: e)]),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: t.s('파일 선택', 'Choose file', 'ファイルを選択'),
            child: InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 130,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary, width: 1.6),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload_file, size: 36, color: AppColors.primary),
                    const SizedBox(height: 6),
                    Text(
                      desktop
                          ? t.s('파일을 끌어다 놓거나 눌러서 고르세요', 'Drop a file here or click to choose', 'ファイルをドラッグするかクリックして選択')
                          : t.s('눌러서 파일을 고르세요', 'Tap to choose a file', 'タップしてファイルを選択'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (file != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FormatPill(
                '${file.name} · ${t.size(file.size)}',
                ext: file.ext,
                trailing: Icons.close,
                onTap: () => setState(() => _file = null),
              ),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 10),
          Text(
            '${t.s('변환 방식', 'Method', '変換方式')}: ${modeLabel(t, modeOf(target, file?.ext ?? '').name)}',
            style: const TextStyle(color: AppColors.sub),
          ),
          const SizedBox(height: 4),
          Text(t.aiNotice, style: const TextStyle(color: AppColors.sub, fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: file == null || _starting ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(t.s('변환 시작', 'Start conversion', '変換開始')),
          ),
        ],
      ),
    );
    final list = ConversionList(
      target: target,
      pending: _pending,
      emptyText: t.s(
        '아직 변환한 파일이 없습니다. 파일을 올리거나 홈 입력창에 말해 주세요.',
        'No conversions yet. Upload a file or ask in the home input.',
        'まだ変換したファイルはありません。ファイルをアップロードするか、ホームの入力欄で話しかけてください。',
      ),
    );
    return PageBody(
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 1000
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 40, child: upload),
                  const SizedBox(width: 16),
                  Expanded(flex: 60, child: list),
                ],
              )
            : Column(children: [upload, const SizedBox(height: 16), list]),
      ),
    );
  }
}
