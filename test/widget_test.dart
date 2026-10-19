import 'package:convertfile/features/calculator/popup/popup_calculator.dart';
import 'package:convertfile/main.dart';
import 'package:convertfile/shared/logic/frame.dart';
import 'package:convertfile/shared/state.dart';
import 'package:convertfile/shared/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs), authUserProvider.overrideWith((ref) => Stream.value(null))]);
}

Widget _app(ProviderContainer c, Widget home) => UncontrolledProviderScope(
  container: c,
  child: ConvertFileApp(home: home),
);

void main() {
  testWidgets('row expands with a tap on phones and only the checkbox checks', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container();
    var expanded = false;
    var checked = false;
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ExpandableRow(
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
              checked: checked,
              onChecked: (v) => setState(() => checked = v),
              header: const Text('header'),
              details: const Text('details'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('details'), findsNothing);
    await tester.tap(find.text('header'));
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget);
    expect(checked, isFalse);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(checked, isTrue);
  });

  testWidgets('selection toggle shows 전체 선택 then 삭제', (tester) async {
    final c = await _container();
    var count = 0;
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                SelectionToggleButton(selectedCount: count, onSelectAll: () => setState(() => count = 3), onDelete: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('전체 선택'), findsOneWidget);
    await tester.tap(find.text('전체 선택'));
    await tester.pump();
    expect(find.text('삭제 (3)'), findsOneWidget);
  });

  testWidgets('largest text level does not overflow the calculator popup', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container();
    c.read(readingProvider.notifier).setFont(5);
    c.read(readingProvider.notifier).setLine(5);
    c.read(calcPopupProvider.notifier).setOpen(true);
    await tester.pumpWidget(
      _app(
        c,
        Scaffold(
          body: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [PopupCalculatorLayer(frame: AppFrame.desktop, area: Size(box.maxWidth, box.maxHeight))],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('계산기'), findsOneWidget);
    for (final k in ['7', '+', '5', '=']) {
      await tester.tap(find.text(k));
    }
    await tester.pump();
    expect(c.read(basicCalcProvider).display, '12');
  });

  test('popup position is stored per frame', () async {
    final c = await _container();
    c.read(calcPopupProvider.notifier).move(AppFrame.phonePortrait, const Offset(40, 50));
    expect(c.read(calcPopupProvider).positionFor(AppFrame.phonePortrait), const Offset(40, 50));
    expect(c.read(calcPopupProvider).positionFor(AppFrame.desktop), const Offset(16, 16));
    final prefs = c.read(prefsProvider);
    expect(prefs.getString('calcPopupPos.phonePortrait'), isNotNull);
  });

  test('reading settings scale by 10% steps', () async {
    final c = await _container();
    final r = c.read(readingProvider);
    expect(r.fontLevel, 3);
    expect(r.lineLevel, 4);
    expect(r.lineHeight, closeTo(1.45, 1e-9));
    c.read(readingProvider.notifier).setFont(5);
    expect(c.read(readingProvider).fontFactor, closeTo(1.2, 1e-9));
  });

  test('calculator keeps the value and carries it between popup and full screen', () async {
    final c = await _container();
    final n = c.read(basicCalcProvider.notifier);
    for (final k in ['1', '2', '×', '3']) {
      n.input(k);
    }
    expect(n.equals(), '12×3 = 36');
    n.input('+');
    n.input('4');
    expect(n.equals(), '36+4 = 40');
    n.input('÷');
    n.input('0');
    expect(n.equals(), isNull);
    expect(c.read(basicCalcProvider).error, isTrue);
  });
}
