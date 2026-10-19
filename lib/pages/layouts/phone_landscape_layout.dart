import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../app_shell.dart';
import 'desktop_layout.dart';

/// Left rail 58 wide (logo = home, 4 group icons). Top strip 46: tabs on the left, header buttons on the right, so
/// the short landscape height goes to the content.
class PhoneLandscapeLayout extends ConsumerWidget {
  const PhoneLandscapeLayout({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final nav = ref.watch(navProvider);
    return Scaffold(
      body: GridBackground(
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: AppDims.rail,
                decoration: const BoxDecoration(
                  color: AppColors.sidebar,
                  border: Border(right: BorderSide(color: AppColors.line)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: t.groupHome,
                        child: InkWell(
                          onTap: () => ref.read(navProvider.notifier).home(),
                          child: const Padding(padding: EdgeInsets.all(4), child: AppLogo(compact: true, size: 34)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final g in MenuGroup.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SideItem(
                            icon: groupIcon(g),
                            label: groupLabel(t, g),
                            selected: !nav.myPage && nav.group == g,
                            iconOnly: true,
                            onTap: () => ref.read(navProvider.notifier).group(g),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      constraints: const BoxConstraints(minHeight: 46),
                      decoration: shellBarDecoration(const Border(bottom: BorderSide(color: AppColors.line))),
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          const Expanded(child: GroupTabsBar(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6))),
                          const HeaderActions(dense: true, compactLogout: true),
                        ],
                      ),
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
