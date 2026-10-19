import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/app_text.dart';
import '../../shared/file_rules.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../app_shell.dart';

/// Header 64 and sidebar 232 with the format and PDF chips (76 icons-only under 1180 wide). Group tabs show above the
/// content only when the sidebar cannot hold them (narrow sidebar, calculator).
class DesktopLayout extends ConsumerWidget {
  const DesktopLayout({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final nav = ref.watch(navProvider);
    final narrow = MediaQuery.sizeOf(context).width < 1180;
    final showTabs = narrow || nav.group == MenuGroup.calc;
    return Scaffold(
      body: GridBackground(
        child: Column(
          children: [
            Container(
              height: AppDims.desktopHeader,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: shellBarDecoration(const Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: t.groupHome,
                    child: InkWell(onTap: () => ref.read(navProvider.notifier).home(), child: const AppLogo(size: 36)),
                  ),
                  const Spacer(),
                  const HeaderActions(),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: narrow ? AppDims.sidebarNarrow : AppDims.sidebarWide,
                    decoration: const BoxDecoration(
                      color: AppColors.sidebar,
                      border: Border(right: BorderSide(color: AppColors.line)),
                    ),
                    child: narrow ? _NarrowSidebar(t: t, nav: nav) : _WideSidebar(t: t, nav: nav),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        if (showTabs) const Align(alignment: Alignment.centerLeft, child: GroupTabsBar()),
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White bar with a soft shadow, shared by every frame's header and rail.
BoxDecoration shellBarDecoration(Border border) => BoxDecoration(
  color: AppColors.paper,
  border: border,
  boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
);

class _WideSidebar extends ConsumerWidget {
  const _WideSidebar({required this.t, required this.nav});

  final AppText t;
  final NavState nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(navProvider.notifier);
    bool on(MenuGroup g) => !nav.myPage && nav.group == g;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      children: [
        SideItem(icon: groupIcon(MenuGroup.home), label: t.groupHome, selected: on(MenuGroup.home), onTap: n.home),
        const SizedBox(height: 14),
        SideItem(
          icon: groupIcon(MenuGroup.convert),
          label: t.groupConvert,
          selected: on(MenuGroup.convert),
          heading: true,
          onTap: () => n.group(MenuGroup.convert),
        ),
        _ChipWrap(
          children: [
            for (final f in TargetFormat.values)
              SideChip(label: formatTabLabel(t, f), selected: on(MenuGroup.convert) && nav.convertTab == f, onTap: () => n.convert(f)),
          ],
        ),
        const SizedBox(height: 14),
        SideItem(
          icon: groupIcon(MenuGroup.pdf),
          label: t.groupPdf,
          selected: on(MenuGroup.pdf),
          heading: true,
          onTap: () => n.group(MenuGroup.pdf),
        ),
        _ChipWrap(
          children: [
            SideChip(label: t.tabMerge, selected: on(MenuGroup.pdf) && nav.pdfTab == PdfTab.merge, onTap: () => n.pdf(PdfTab.merge)),
            SideChip(label: t.tabEdit, selected: on(MenuGroup.pdf) && nav.pdfTab == PdfTab.edit, onTap: () => n.pdf(PdfTab.edit)),
          ],
        ),
        const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1)),
        SideItem(icon: groupIcon(MenuGroup.calc), label: t.groupCalc, selected: on(MenuGroup.calc), onTap: () => n.group(MenuGroup.calc)),
      ],
    );
  }
}

class _NarrowSidebar extends ConsumerWidget {
  const _NarrowSidebar({required this.t, required this.nav});

  final AppText t;
  final NavState nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
    children: [
      for (final g in MenuGroup.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SideItem(
            icon: groupIcon(g),
            label: groupLabel(t, g),
            selected: !nav.myPage && nav.group == g,
            iconOnly: true,
            onTap: () => ref.read(navProvider.notifier).group(g),
          ),
        ),
    ],
  );
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
    child: Wrap(spacing: 6, runSpacing: 6, children: children),
  );
}

/// Sidebar row: light pill with a left accent bar when selected.
class SideItem extends StatelessWidget {
  const SideItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.heading = false,
    this.iconOnly = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool heading;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected && !heading;
    final item = Material(
      color: fill ? AppColors.sideSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: fill ? AppColors.primary : Colors.transparent, width: 4)),
          ),
          padding: EdgeInsets.symmetric(vertical: heading ? 6 : 11, horizontal: iconOnly ? 0 : 10),
          child: Row(
            mainAxisAlignment: iconOnly ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.ink, size: 22),
              if (!iconOnly) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected ? AppColors.primary : AppColors.ink, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: iconOnly ? Tooltip(message: label, child: item) : item,
      ),
    );
  }
}

class SideChip extends StatelessWidget {
  const SideChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: Material(
        color: selected ? AppColors.primary : AppColors.paper,
        shape: pillBorder,
        child: InkWell(
          customBorder: pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: selected ? Colors.white : AppColors.ink),
            ),
          ),
        ),
      ),
    ),
  );
}
