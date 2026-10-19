import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../app_shell.dart';

/// Header 64, sidebar 232 (76 icons-only under 1180 wide), group tabs above the content.
class DesktopLayout extends ConsumerWidget {
  const DesktopLayout({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final nav = ref.watch(navProvider);
    final narrow = MediaQuery.sizeOf(context).width < 1180;
    return Scaffold(
      body: GridBackground(
        child: Column(
          children: [
            Container(
              height: AppDims.desktopHeader,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                border: Border(
                  bottom: BorderSide(color: AppColors.ink, width: AppDims.borderWidth),
                ),
              ),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: t.groupHome,
                    child: InkWell(onTap: () => ref.read(navProvider.notifier).home(), child: const AppLogo()),
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
                      color: AppColors.paper,
                      border: Border(
                        right: BorderSide(color: AppColors.ink, width: AppDims.borderWidth),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      children: [
                        for (final g in MenuGroup.values)
                          _SideItem(
                            icon: groupIcon(g),
                            label: groupLabel(t, g),
                            selected: !nav.myPage && nav.group == g,
                            narrow: narrow,
                            onTap: () => ref.read(navProvider.notifier).group(g),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Align(alignment: Alignment.centerLeft, child: GroupTabsBar()),
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

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.narrow, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final bool narrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.ink;
    final item = Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            mainAxisAlignment: narrow ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              if (!narrow) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: narrow ? Tooltip(message: label, child: item) : item,
      ),
    );
  }
}
