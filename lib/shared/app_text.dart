import 'package:intl/intl.dart';

enum AppLang {
  ko('ko', '한국어'),
  en('en', 'English'),
  ja('ja', '日本語');

  const AppLang(this.code, this.label);

  final String code;
  final String label;

  AppLang get next => AppLang.values[(index + 1) % AppLang.values.length];

  static AppLang fromCode(String? code) => AppLang.values.firstWhere((l) => l.code == code, orElse: () => AppLang.ko);
}

/// Screen sentences. Every entry carries all three languages so no key can be missing in one of them.
class AppText {
  const AppText(this.lang);

  final AppLang lang;

  String s(String ko, String en, String ja) => switch (lang) {
    AppLang.ko => ko,
    AppLang.en => en,
    AppLang.ja => ja,
  };

  String number(num v, {int decimals = 0}) {
    final f = NumberFormat.decimalPatternDigits(locale: lang.code, decimalDigits: decimals);
    return f.format(v);
  }

  String size(int bytes) {
    if (bytes < 1024 * 1024) return '${number(bytes / 1024, decimals: 1)}KB';
    if (bytes >= 1024 * 1024 * 1024) return '${number(bytes / (1024 * 1024 * 1024), decimals: 1)}GB';
    return '${number(bytes / (1024 * 1024), decimals: 1)}MB';
  }

  String limitLabel(int bytes) => bytes >= 1024 * 1024 * 1024 ? '1GB' : '${bytes ~/ (1024 * 1024)}MB';

  String dateTime(DateTime d) => DateFormat.yMd(lang.code).add_Hm().format(d);

  // App
  String get appName => 'ConvertFile';
  String get tagline =>
      s('말하거나 파일을 넣으면, 필요한 형식으로 바꿔 드립니다.', 'Speak or drop a file, and we convert it to the format you need.', '話すかファイルを入れると、必要な形式に変換します。');

  // Groups and tabs
  String get groupHome => s('AI 홈', 'AI Home', 'AIホーム');
  String get groupConvert => s('파일 변환', 'Convert', 'ファイル変換');
  String get groupPdf => s('PDF 도구', 'PDF Tools', 'PDFツール');
  String get groupCalc => s('계산기', 'Calculator', '電卓');
  String get tabMerge => s('합치기', 'Merge', '結合');
  String get tabEdit => s('편집', 'Edit', '編集');
  String get tabBasic => s('기본', 'Basic', '基本');
  String get tabScientific => s('공학', 'Scientific', '関数');
  String get tabFx => s('환율', 'Exchange', '為替');
  String get tabBusiness => s('업무', 'Business', '業務');
  String get myPage => s('마이페이지', 'My page', 'マイページ');

  // Header
  String get calculator => s('계산기', 'Calculator', '電卓');
  String get logout => s('로그아웃', 'Log out', 'ログアウト');
  String get language => s('언어', 'Language', '言語');

  // Common
  String get cancel => s('취소', 'Cancel', 'キャンセル');
  String get confirm => s('확인', 'OK', 'OK');
  String get delete => s('삭제', 'Delete', '削除');
  String get selectAll => s('전체 선택', 'Select all', 'すべて選択');
  String get close => s('닫기', 'Close', '閉じる');
  String get refresh => s('새로고침', 'Refresh', '更新');
  String get expand => s('펼치기', 'Expand', '展開');
  String get dragHandle => s('끌기 손잡이', 'Drag handle', 'ドラッグハンドル');
  String get moveUp => s('위로', 'Up', '上へ');
  String get moveDown => s('아래로', 'Down', '下へ');
  String get select => s('선택', 'Select', '選択');
  String get guest => s('게스트', 'Guest', 'ゲスト');
  String deleteConfirm(int n) =>
      s('선택한 $n개를 삭제합니다. 파일도 함께 지워집니다.', 'Delete $n selected items. Their files are deleted too.', '選択した$n件を削除します。ファイルも削除されます。');
  String get runningCannotDelete =>
      s('변환 중인 항목은 끝난 뒤 지울 수 있습니다.', 'Items being converted can be deleted after they finish.', '変換中の項目は終了後に削除できます。');
  String get aiNotice => s(
    'AI 기능을 쓰면 문서 내용이 Google Gemini로 전송됩니다.',
    'When you use AI features, document content is sent to Google Gemini.',
    'AI機能を使うと、文書の内容がGoogle Geminiに送信されます。',
  );
  String get backupBanner => s(
    'Firebase 연결이 끊겨 보조 DB에서 읽는 중입니다. 내려받기는 연결 후 가능합니다.',
    'Firebase is disconnected, so data is read from the backup DB. Downloads resume after reconnecting.',
    'Firebaseとの接続が切れたため、補助DBから読み込んでいます。ダウンロードは接続後に可能です。',
  );

  // Status
  String get statusQueued => s('대기 중', 'Queued', '待機中');
  String get statusRunning => s('변환 중', 'Converting', '変換中');
  String get statusDone => s('완료', 'Done', '完了');
  String get statusFailed => s('실패', 'Failed', '失敗');
  String uploading(int p) => s('올리는 중 $p%', 'Uploading $p%', 'アップロード中 $p%');

  // Calculator
  String get calcOff => 'Off';
  String get fullScreen => s('전체화면', 'Full screen', '全画面');
  String get calcHistoryEmpty => s('= 을 누르면 계산 결과가 여기에 남습니다.', 'Press = and results are kept here.', '= を押すと計算結果がここに残ります。');
  String get calcError => s('계산할 수 없습니다', 'Cannot calculate', '計算できません');

  // Reading settings
  String get fontSize => s('글자크기', 'Text size', '文字サイズ');
  String get lineSpacing => s('줄간 거리', 'Line spacing', '行間');
}
