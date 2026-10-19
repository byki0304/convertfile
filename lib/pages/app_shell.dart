import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/account_actions.dart';
import '../features/account/my_page.dart';
import '../features/ai_home/ai_home_page.dart';
import '../features/calculator/full/full_calculator.dart';
import '../features/calculator/popup/popup_calculator.dart';
import '../features/convert/convert_page.dart';
import '../features/convert/done_watcher.dart';
import '../features/pdf_edit/pdf_edit_page.dart';
import '../features/pdf_merge/pdf_merge_page.dart';
import '../shared/app_text.dart';
import '../shared/file_rules.dart';
import '../shared/logic/frame.dart';
import '../shared/state.dart';
import '../shared/theme.dart';
import 'layouts/desktop_layout.dart';
import 'layouts/phone_landscape_layout.dart';
import 'layouts/portrait_layout.dart';

IconData groupIcon(MenuGroup g) => switch (g) {
  MenuGroup.home => Icons.auto_awesome,
  MenuGroup.convert => Icons.swap_horiz_rounded,
  MenuGroup.pdf => Icons.picture_as_pdf_outlined,
  MenuGroup.calc => Icons.calculate_outlined,
};

String groupLabel(AppText t, MenuGroup g) => switch (g) {
  MenuGroup.home => t.groupHome,
  MenuGroup.convert => t.groupConvert,
  MenuGroup.pdf => t.groupPdf,
  MenuGroup.calc => t.groupCalc,
};

String formatTabLabel(AppText t, TargetFormat f) => switch (f) {
  TargetFormat.hwpx => t.s('한글', 'Hangul', 'ハングル'),
  TargetFormat.txt => t.s('텍스트', 'Text', 'テキスト'),
  _ => f.label,
};

class TabItem {
  const TabItem(this.label, this.selected, this.onTap);

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

List<TabItem> groupTabs(WidgetRef ref) {
  final t = ref.watch(textProvider);
  final nav = ref.watch(navProvider);
  final n = ref.read(navProvider.notifier);
  if (nav.myPage) return const [];
  return switch (nav.group) {
    MenuGroup.home => const [],
    MenuGroup.convert => [for (final f in TargetFormat.values) TabItem(formatTabLabel(t, f), nav.convertTab == f, () => n.convert(f))],
    MenuGroup.pdf => [
      TabItem(t.tabMerge, nav.pdfTab == PdfTab.merge, () => n.pdf(PdfTab.merge)),
      TabItem(t.tabEdit, nav.pdfTab == PdfTab.edit, () => n.pdf(PdfTab.edit)),
    ],
    MenuGroup.calc => [
      TabItem(t.tabBasic, nav.calcTab == CalcTab.basic, () => n.calc(CalcTab.basic)),
      TabItem(t.tabScientific, nav.calcTab == CalcTab.scientific, () => n.calc(CalcTab.scientific)),
      TabItem(t.tabFx, nav.calcTab == CalcTab.fx, () => n.calc(CalcTab.fx)),
      TabItem(t.tabBusiness, nav.calcTab == CalcTab.business, () => n.calc(CalcTab.business)),
    ],
  };
}

/// Horizontal tab chips; scrolls sideways when they do not fit.
class GroupTabsBar extends ConsumerWidget {
  const GroupTabsBar({super.key, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = groupTabs(ref);
    if (tabs.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: tab.selected ? AppColors.primary : AppColors.paper,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.ink, width: 1.4),
                ),
                child: Semantics(
                  button: true,
                  selected: tab.selected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: tab.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        tab.label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: tab.selected ? Colors.white : AppColors.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Language, calculator, logout and avatar buttons (same order in every frame).
class HeaderActions extends ConsumerWidget {
  const HeaderActions({super.key, this.compactLogout = false, this.dense = false});

  final bool compactLogout;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final lang = ref.watch(langProvider);
    final user = ref.watch(authUserProvider).value;
    final gap = SizedBox(width: dense ? 4 : 8);
    final pad = EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 6 : 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: t.language,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: pad, minimumSize: Size.zero),
            onPressed: () => ref.read(langProvider.notifier).cycle(),
            child: Text(lang.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        gap,
        Tooltip(
          message: t.calculator,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: pad, minimumSize: Size.zero),
            onPressed: () => ref.read(calcPopupProvider.notifier).toggle(),
            child: const Icon(Icons.calculate_outlined, size: 20),
          ),
        ),
        gap,
        if (compactLogout)
          IconButton(tooltip: t.logout, onPressed: () => logoutFlow(context, ref), icon: const Icon(Icons.logout))
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(padding: pad, minimumSize: Size.zero),
            onPressed: () => logoutFlow(context, ref),
            child: Text(t.logout),
          ),
        gap,
        Semantics(
          button: true,
          label: t.myPage,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => ref.read(navProvider.notifier).openMyPage(),
            child: UserAvatar(user: user, radius: dense ? 15 : 18),
          ),
        ),
      ],
    );
  }
}

/// Current menu content plus the popup calculator overlay, kept under one GlobalKey so a frame change only re-parents it.
class MenuBody extends ConsumerWidget {
  const MenuBody({super.key, required this.frame});

  final AppFrame frame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navProvider);
    final Widget page = nav.myPage
        ? const MyPage()
        : switch (nav.group) {
            MenuGroup.home => const AiHomePage(),
            MenuGroup.convert => ConvertPage(key: ValueKey(nav.convertTab), target: nav.convertTab),
            MenuGroup.pdf => nav.pdfTab == PdfTab.merge ? const PdfMergePage() : const PdfEditPage(),
            MenuGroup.calc => FullCalculator(tab: nav.calcTab),
          };
    final pageKey = nav.myPage ? 'my' : '${nav.group.name}/${nav.convertTab.name}/${nav.pdfTab.name}/${nav.calcTab.name}';
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                const BackupBanner(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: KeyedSubtree(key: ValueKey(pageKey), child: page),
                  ),
                ),
              ],
            ),
          ),
          PopupCalculatorLayer(frame: frame, area: Size(c.maxWidth, c.maxHeight)),
        ],
      ),
    );
  }
}

class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(backupModeProvider)) return const SizedBox.shrink();
    final t = ref.watch(textProvider);
    return Container(
      width: double.infinity,
      color: AppColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(t.backupBanner, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final frame = frameOf(size);
    final body = ConversionDoneWatcher(
      key: _bodyKey,
      child: MenuBody(frame: frame),
    );
    return switch (frame) {
      AppFrame.desktop => DesktopLayout(body: body),
      AppFrame.phoneLandscape => PhoneLandscapeLayout(body: body),
      AppFrame.phonePortrait => PortraitLayout(body: body),
    };
  }
}
