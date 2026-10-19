import 'app_text.dart';
import 'file_rules.dart';

String formatList(List<String> exts) => exts.map((e) => e.toUpperCase()).join(', ');

String guestHint(AppText t) => t.s('로그인하면 1GB까지 쓸 수 있습니다.', 'Log in to use up to 1GB.', 'ログインすると1GBまで使えます。');

String fileTooLarge(AppText t, bool guest) {
  final l = t.limitLabel(Limits.fileBytes(guest));
  final m = t.s('파일은 $l까지 올릴 수 있습니다.', 'Files can be up to $l.', 'ファイルは$lまでアップロードできます。');
  return guest ? '$m ${guestHint(t)}' : m;
}

String pdfToolTooLarge(AppText t, bool guest) {
  final l = t.limitLabel(Limits.pdfToolBytes(guest));
  final m = t.s('PDF 도구는 한 번에 $l까지 쓸 수 있습니다.', 'PDF tools handle up to $l at a time.', 'PDFツールは一度に$lまで使えます。');
  return guest ? '$m ${guestHint(t)}' : m;
}

String pdfToolWarn(AppText t) => t.s(
  '파일이 커서 기기에 따라 느리거나 멈출 수 있습니다.',
  'The files are large and may be slow or freeze on some devices.',
  'ファイルが大きいため、端末によっては遅くなったり止まったりすることがあります。',
);

String quotaExceeded(AppText t, bool guest) {
  final l = t.limitLabel(Limits.dailyBytes(guest));
  final m = t.s(
    '오늘 쓸 수 있는 용량($l)을 모두 썼습니다. 내일 다시 이용해 주세요.',
    "You've used today's limit ($l). Please try again tomorrow.",
    '本日の使用量($l)をすべて使いました。明日またご利用ください。',
  );
  return guest ? '$m ${guestHint(t)}' : m;
}

String aiQuotaExceeded(AppText t, bool guest) {
  final n = Limits.aiCalls(guest);
  return t.s(
    '오늘 AI 사용 횟수($n회)를 모두 썼습니다. 파일 변환과 PDF 도구는 계속 쓸 수 있습니다.',
    "You've used today's AI limit ($n). File conversion and PDF tools are still available.",
    '本日のAI使用回数($n回)をすべて使いました。ファイル変換とPDFツールは引き続き使えます。',
  );
}

String unsupportedFormat(AppText t, List<String> exts) {
  final l = formatList(exts);
  return t.s('이 메뉴에서는 $l 파일만 올릴 수 있습니다.', 'This menu accepts only $l files.', 'このメニューでは$lファイルのみアップロードできます。');
}

String sameFormat(AppText t, String ext) {
  final f = ext.toUpperCase();
  return t.s(
    '이미 $f 파일입니다. 다른 결과 형식을 골라 주세요.',
    'This is already a $f file. Choose a different result format.',
    'すでに$fファイルです。別の変換形式を選んでください。',
  );
}

String pdfOnly(AppText t) => t.s('PDF 파일만 쓸 수 있습니다.', 'Only PDF files can be used.', 'PDFファイルのみ使えます。');

String encryptedFile(AppText t) => t.s('암호가 걸린 파일은 변환할 수 없습니다.', 'Password-protected files cannot be converted.', 'パスワード付きファイルは変換できません。');

String genericError(AppText t) =>
    t.s('변환하지 못했습니다. 연결 또는 파일을 확인해 주세요.', 'Could not convert. Check your connection or the file.', '変換できませんでした。接続またはファイルを確認してください。');

/// Server and engine error codes to screen sentences.
String errorMessage(AppText t, String? code, {bool guest = false, TargetFormat? target, String? ext}) {
  switch (code) {
    case 'file-too-large':
      return fileTooLarge(t, guest);
    case 'unsupported-format':
      return target == null ? genericError(t) : unsupportedFormat(t, acceptedInputs[target]!);
    case 'same-format':
      return sameFormat(t, ext ?? target?.ext ?? '');
    case 'encrypted-file':
      return encryptedFile(t);
    case 'protected-hwp':
      return t.s('배포용(보호) 한글 문서는 변환할 수 없습니다.', 'Distribution-protected Hangul documents cannot be converted.', '配布用(保護)のハングル文書は変換できません。');
    case 'no-text-found':
      return t.s('파일에서 글자를 찾지 못했습니다.', 'No text was found in the file.', 'ファイルから文字が見つかりませんでした。');
    case 'no-table-found':
      return t.s(
        '표를 찾지 못했습니다. 표가 있는 문서를 올려 주세요.',
        'No tables were found. Upload a document that has tables.',
        '表が見つかりませんでした。表のある文書をアップロードしてください。',
      );
    case 'engine-timeout':
      return t.s(
        '변환 시간이 너무 오래 걸려 멈췄습니다. 파일을 나눠서 다시 시도해 주세요.',
        'Conversion took too long and was stopped. Split the file and try again.',
        '変換に時間がかかりすぎたため停止しました。ファイルを分けて再度お試しください。',
      );
    case 'ai-unavailable':
      return t.s(
        'AI 키가 아직 없습니다. 파일 변환과 PDF 도구는 사용할 수 있습니다.',
        'The AI key is not set yet. File conversion and PDF tools are available.',
        'AIキーがまだありません。ファイル変換とPDFツールは使えます。',
      );
    case 'quota-exceeded':
      return quotaExceeded(t, guest);
    case 'ai-quota-exceeded':
      return aiQuotaExceeded(t, guest);
    case 'source-too-large-for-summary':
      return t.s(
        '파일이 커서 요약할 수 없습니다. 200MB 이하 파일만 요약할 수 있습니다.',
        'The file is too large to summarize. Only files up to 200MB can be summarized.',
        'ファイルが大きいため要約できません。200MB以下のファイルのみ要約できます。',
      );
    case 'summary-needs-conversion':
      return t.s('이 형식은 먼저 텍스트로 변환한 뒤 요약할 수 있습니다.', 'Convert this format to text first, then summarize it.', 'この形式は先にテキストに変換してから要約できます。');
    default:
      return genericError(t);
  }
}
