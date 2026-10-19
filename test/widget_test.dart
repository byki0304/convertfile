import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convertfile/features/account/account_actions.dart';
import 'package:convertfile/features/ai_home/ai_home_page.dart';
import 'package:convertfile/features/calculator/popup/popup_calculator.dart';
import 'package:convertfile/features/convert/recent_panel.dart';
import 'package:convertfile/main.dart';
import 'package:convertfile/pages/app_shell.dart';
import 'package:convertfile/pages/layouts/desktop_layout.dart';
import 'package:convertfile/shared/file_rules.dart';
import 'package:convertfile/shared/logic/frame.dart';
import 'package:convertfile/shared/state.dart';
import 'package:convertfile/shared/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  testWidgets('portrait tabs split into two rows and header buttons keep their order', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container();
    c.read(navProvider.notifier).convert(TargetFormat.md);
    await tester.pumpWidget(
      _app(c, const Scaffold(body: Column(children: [HeaderActions(dense: true, compactLogout: true), GroupTabsBar(twoRows: true)]))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final t = c.read(textProvider);
    double y(TargetFormat f) => tester.getCenter(find.text(formatTabLabel(t, f))).dy;
    expect(y(TargetFormat.md), closeTo(y(TargetFormat.pptx), 0.5));
    expect(y(TargetFormat.xlsx), greaterThan(y(TargetFormat.md) + 10));
    expect(y(TargetFormat.xlsx), closeTo(y(TargetFormat.txt), 0.5));

    double x(Finder f) => tester.getCenter(f).dx;
    final order = [find.text('한국어'), find.byIcon(Icons.calculate_outlined), find.byType(UserAvatar), find.byIcon(Icons.logout_rounded)];
    for (var i = 1; i < order.length; i++) {
      expect(x(order[i]), greaterThan(x(order[i - 1])));
    }
  });

  testWidgets('desktop sidebar chips switch menus and stay reachable by screen readers', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final c = await _container();
    await tester.pumpWidget(_app(c, const DesktopLayout(body: SizedBox.expand())));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(GroupTabsBar), findsNothing);
    await tester.tap(find.text('Excel'));
    await tester.pump();
    expect(c.read(navProvider).convertTab, TargetFormat.xlsx);
    expect(c.read(navProvider).group, MenuGroup.convert);
    for (final label in ['Word', '합치기', '계산기']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label).first);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    await tester.tap(find.text('합치기'));
    await tester.pump();
    expect(c.read(navProvider).pdfTab, PdfTab.merge);
    handle.dispose();
  });

  for (final size in const [Size(390, 844), Size(844, 390), Size(1440, 900)]) {
    testWidgets('AI home lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _container();
      await tester.pumpWidget(_app(c, const Scaffold(body: AiHomePage())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(PresetPill), findsNWidgets(3));
      expect(find.byType(RecentConversionsPanel), findsOneWidget);
      expect(find.byType(UploadDropZone), size.height < 500 ? findsNothing : findsOneWidget);
    });
  }

  test('manifest, html and every platform folder point to existing icons of the right size', () {
    (int, int) pngSize(String path) {
      final b = File(path).readAsBytesSync();
      final d = ByteData.sublistView(b);
      return (d.getUint32(16), d.getUint32(20));
    }

    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    for (final icon in (manifest['icons'] as List).cast<Map<String, dynamic>>()) {
      final px = int.parse((icon['sizes'] as String).split('x').first);
      expect(pngSize('web/${icon['src']}'), (px, px), reason: icon['src'] as String);
    }
    final html = File('web/index.html').readAsStringSync();
    for (final m in RegExp(r'href="(icons/[^"]+|favicon\.ico)"').allMatches(html)) {
      expect(File('web/${m[1]}').existsSync(), isTrue, reason: m[1]);
    }
    final ios = jsonDecode(File('app_icons/ios/AppIcon.appiconset/Contents.json').readAsStringSync()) as Map<String, dynamic>;
    for (final img in (ios['images'] as List).cast<Map<String, dynamic>>()) {
      final pt = double.parse((img['size'] as String).split('x').first);
      final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
      final px = (pt * scale).round();
      expect(pngSize('app_icons/ios/AppIcon.appiconset/${img['filename']}'), (px, px));
    }
    for (final (dir, px) in const [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
      expect(pngSize('app_icons/android/mipmap-$dir/ic_launcher.png'), (px, px));
      expect(pngSize('app_icons/android/mipmap-$dir/ic_launcher_round.png'), (px, px));
    }
    for (final f in [
      'app_icons/android/mipmap-anydpi-v26/ic_launcher.xml',
      'app_icons/android/playstore-icon-512.png',
      'app_icons/tablet/ipad/ipad-167.png',
      'app_icons/tablet/android/tablet-xxxhdpi-192.png',
      'app_icons/desktop/windows/app_icon.ico',
      'app_icons/desktop/macos/AppIcon.icns',
      'app_icons/desktop/png/icon-1024.png',
      'web/browserconfig.xml',
      'web/intro/intro.mp4',
    ]) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
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
