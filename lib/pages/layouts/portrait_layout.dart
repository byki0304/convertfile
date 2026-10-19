import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../app_shell.dart';

/// Header 56 (logo, then language / calculator / my page / logout on the right), tab chips in two rows below it,
/// bottom tabs (hidden while the keyboard is up).
class PortraitLayout extends ConsumerWidget {
  const PortraitLayout({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final nav = ref.watch(navProvider);
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    final narrow = mq.size.width < 370;
    final selected = nav.myPage ? -1 : nav.group.index;
    return Scaffold(
      body: GridBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                height: AppDims.portraitHeader,
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      child: InkWell(
                        onTap: () => ref.read(navProvider.notifier).home(),
                        child: AppLogo(compact: narrow, size: 30),
                      ),
                    ),
                    const Spacer(),
                    const Flexible(flex: 0, child: FittedBox(child: HeaderActions(dense: true, compactLogout: true))),
                  ],
                ),
              ),
              const GroupTabsBar(twoRows: true),
              Expanded(child: body),
            ],
          ),
        ),
      ),
      bottomNavigationBar: keyboard
          ? null
          : NavigationBar(
              height: 64,
              backgroundColor: AppColors.paper,
              indicatorColor: AppColors.accent,
              selectedIndex: selected < 0 ? 0 : selected,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (i) => ref.read(navProvider.notifier).group(MenuGroup.values[i]),
              destinations: [for (final g in MenuGroup.values) NavigationDestination(icon: Icon(groupIcon(g)), label: groupLabel(t, g))],
            ),
    );
  }
}
