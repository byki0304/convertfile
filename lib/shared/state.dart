import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_text.dart';
import 'file_rules.dart';
import 'logic/calc_engine.dart';
import 'logic/frame.dart';
import 'theme.dart';
import 'web/bridge.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

// ---------- Locale & reading ----------

class LangNotifier extends Notifier<AppLang> {
  @override
  AppLang build() => AppLang.fromCode(ref.read(prefsProvider).getString('locale'));

  void set(AppLang lang) {
    state = lang;
    ref.read(prefsProvider).setString('locale', lang.code);
  }

  void cycle() => set(state.next);
}

final langProvider = NotifierProvider<LangNotifier, AppLang>(LangNotifier.new);
final textProvider = Provider<AppText>((ref) => AppText(ref.watch(langProvider)));

class ReadingNotifier extends Notifier<ReadingSettings> {
  @override
  ReadingSettings build() {
    final p = ref.read(prefsProvider);
    return ReadingSettings(fontLevel: p.getInt('fontLevel') ?? 3, lineLevel: p.getInt('lineLevel') ?? 4);
  }

  void setFont(int level) {
    state = state.copyWith(fontLevel: level.clamp(1, 5));
    ref.read(prefsProvider).setInt('fontLevel', state.fontLevel);
  }

  void setLine(int level) {
    state = state.copyWith(lineLevel: level.clamp(1, 5));
    ref.read(prefsProvider).setInt('lineLevel', state.lineLevel);
  }
}

final readingProvider = NotifierProvider<ReadingNotifier, ReadingSettings>(ReadingNotifier.new);

// ---------- Auth ----------

final authUserProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.userChanges());

final isGuestProvider = Provider<bool>((ref) => ref.watch(authUserProvider).value?.isAnonymous ?? true);

final uidProvider = Provider<String?>((ref) => ref.watch(authUserProvider).value?.uid);

// ---------- Navigation ----------

enum MenuGroup { home, convert, pdf, calc }

enum PdfTab { merge, edit }

enum CalcTab { basic, scientific, fx, business }

@immutable
class NavState {
  const NavState({
    this.group = MenuGroup.home,
    this.convertTab = TargetFormat.md,
    this.pdfTab = PdfTab.merge,
    this.calcTab = CalcTab.basic,
    this.myPage = false,
  });

  final MenuGroup group;
  final TargetFormat convertTab;
  final PdfTab pdfTab;
  final CalcTab calcTab;
  final bool myPage;

  NavState copyWith({MenuGroup? group, TargetFormat? convertTab, PdfTab? pdfTab, CalcTab? calcTab, bool? myPage}) => NavState(
    group: group ?? this.group,
    convertTab: convertTab ?? this.convertTab,
    pdfTab: pdfTab ?? this.pdfTab,
    calcTab: calcTab ?? this.calcTab,
    myPage: myPage ?? this.myPage,
  );
}

class NavNotifier extends Notifier<NavState> {
  @override
  NavState build() => const NavState();

  /// Set by pages with unsaved work; returns true when leaving is allowed.
  Future<bool> Function()? leaveGuard;

  Future<bool> _canLeave() async => leaveGuard == null || await leaveGuard!();

  Future<void> _go(NavState next) async {
    if (!await _canLeave()) return;
    state = next;
  }

  Future<void> group(MenuGroup g) => _go(state.copyWith(group: g, myPage: false));
  Future<void> convert(TargetFormat f) => _go(state.copyWith(group: MenuGroup.convert, convertTab: f, myPage: false));
  Future<void> pdf(PdfTab t) => _go(state.copyWith(group: MenuGroup.pdf, pdfTab: t, myPage: false));
  Future<void> calc(CalcTab t) => _go(state.copyWith(group: MenuGroup.calc, calcTab: t, myPage: false));
  Future<void> openMyPage() => _go(state.copyWith(myPage: true));
  Future<void> home() => group(MenuGroup.home);
}

final navProvider = NotifierProvider<NavNotifier, NavState>(NavNotifier.new);

// ---------- Hand-offs between menus ----------

@immutable
class ConvertHandoff {
  const ConvertHandoff(this.file, this.target, {this.autoStart = false});

  final PickedFile file;
  final TargetFormat target;
  final bool autoStart;
}

class ConvertHandoffNotifier extends Notifier<ConvertHandoff?> {
  @override
  ConvertHandoff? build() => null;

  void set(ConvertHandoff? v) => state = v;
}

final convertHandoffProvider = NotifierProvider<ConvertHandoffNotifier, ConvertHandoff?>(ConvertHandoffNotifier.new);

/// A PDF passed to the merge or edit tool (from AI home, or a conversion result).
@immutable
class PdfHandoff {
  const PdfHandoff({required this.tab, this.file, this.bytes, this.name});

  final PdfTab tab;
  final PickedFile? file;
  final Uint8List? bytes;
  final String? name;
}

class PdfHandoffNotifier extends Notifier<PdfHandoff?> {
  @override
  PdfHandoff? build() => null;

  void set(PdfHandoff? v) => state = v;
}

final pdfHandoffProvider = NotifierProvider<PdfHandoffNotifier, PdfHandoff?>(PdfHandoffNotifier.new);

@immutable
class CalcHandoff {
  const CalcHandoff({required this.tab, this.input = '', this.currency});

  final CalcTab tab;
  final String input;
  final String? currency;
}

class CalcHandoffNotifier extends Notifier<CalcHandoff?> {
  @override
  CalcHandoff? build() => null;

  void set(CalcHandoff? v) => state = v;
}

final calcHandoffProvider = NotifierProvider<CalcHandoffNotifier, CalcHandoff?>(CalcHandoffNotifier.new);

/// Shown above all menus while the primary DB stream is failing.
class BackupModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final backupModeProvider = NotifierProvider<BackupModeNotifier, bool>(BackupModeNotifier.new);

// ---------- Calculator ----------

@immutable
class CalcState {
  const CalcState({this.expr = '', this.display = '0', this.evaluated = false, this.error = false});

  final String expr;
  final String display;
  final bool evaluated;
  final bool error;
}

class CalcNotifier extends Notifier<CalcState> {
  CalcNotifier({this.scientific = false});

  final bool scientific;
  bool degrees = true;

  @override
  CalcState build() => const CalcState();

  static const _ops = '+-×÷^';

  void input(String key) {
    var s = state;
    if (s.evaluated || s.error) {
      final startsWithOp = _ops.contains(key) || key == '%';
      s = CalcState(expr: s.error || !startsWithOp ? '' : s.display);
    }
    var expr = s.expr;
    if (_ops.contains(key) && key != '-' && expr.isNotEmpty && _ops.contains(expr[expr.length - 1])) {
      expr = expr.substring(0, expr.length - 1);
    }
    if (_ops.contains(key) && key != '-' && expr.isEmpty) expr = '0';
    if (CalcEngine.functions.contains(key)) key = '$key(';
    expr += key;
    state = CalcState(expr: expr, display: expr);
  }

  void backspace() {
    if (state.evaluated || state.error) return clear();
    var e = state.expr;
    if (e.isEmpty) return;
    final fn = RegExp(r'(sin|cos|tan|log|ln|√)\($').firstMatch(e);
    e = fn != null ? e.substring(0, fn.start) : e.substring(0, e.length - 1);
    state = CalcState(expr: e, display: e.isEmpty ? '0' : e);
  }

  void clear() => state = const CalcState();

  void setValue(String value) => state = CalcState(display: value, evaluated: true);

  /// Returns the history line on success.
  String? equals() {
    if (state.expr.isEmpty) return null;
    try {
      final v = CalcEngine(degrees: degrees).evaluate(state.expr);
      final r = CalcEngine.format(v);
      final line = '${state.expr} = $r';
      state = CalcState(expr: state.expr, display: r, evaluated: true);
      return line;
    } on CalcException {
      state = CalcState(expr: state.expr, display: state.expr, error: true);
      return null;
    }
  }

  void toggleDegrees() {
    degrees = !degrees;
    state = CalcState(expr: state.expr, display: state.display, evaluated: state.evaluated, error: state.error);
  }
}

final basicCalcProvider = NotifierProvider<CalcNotifier, CalcState>(CalcNotifier.new);
final sciCalcProvider = NotifierProvider<CalcNotifier, CalcState>(() => CalcNotifier(scientific: true));

class CalcHistoryNotifier extends Notifier<List<String>> {
  static const max = 100;

  late String _key;

  @override
  List<String> build() {
    _key = 'calcHistory.${ref.watch(uidProvider) ?? 'none'}';
    return ref.read(prefsProvider).getStringList(_key) ?? const [];
  }

  void add(String line) {
    state = [line, ...state].take(max).toList();
    ref.read(prefsProvider).setStringList(_key, state);
  }

  void clearAll() {
    state = const [];
    ref.read(prefsProvider).remove(_key);
  }
}

final calcHistoryProvider = NotifierProvider<CalcHistoryNotifier, List<String>>(CalcHistoryNotifier.new);

@immutable
class CalcPopupState {
  const CalcPopupState({this.open = false, this.positions = const {}});

  final bool open;
  final Map<AppFrame, Offset> positions;

  Offset positionFor(AppFrame f) => positions[f] ?? const Offset(16, 16);
}

class CalcPopupNotifier extends Notifier<CalcPopupState> {
  @override
  CalcPopupState build() {
    final p = ref.read(prefsProvider);
    final pos = <AppFrame, Offset>{};
    for (final f in AppFrame.values) {
      final raw = p.getString('calcPopupPos.${f.name}');
      if (raw == null) continue;
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        pos[f] = Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
      } catch (_) {}
    }
    return CalcPopupState(positions: pos);
  }

  void setOpen(bool v) => state = CalcPopupState(open: v, positions: state.positions);

  void toggle() => setOpen(!state.open);

  void move(AppFrame f, Offset pos) {
    state = CalcPopupState(open: state.open, positions: {...state.positions, f: pos});
    ref.read(prefsProvider).setString('calcPopupPos.${f.name}', jsonEncode({'x': pos.dx, 'y': pos.dy}));
  }
}

final calcPopupProvider = NotifierProvider<CalcPopupNotifier, CalcPopupState>(CalcPopupNotifier.new);
