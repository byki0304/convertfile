import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../app_shell.dart';

/// Left rail 58 wide (logo = home, 4 group icons). Top strip: tabs on the left, header buttons on the right.
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
                  color: AppColors.paper,
                  border: Border(
                    right: BorderSide(color: AppColors.ink, width: AppDims.borderWidth),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Semantics(
                        button: true,
                        label: t.groupHome,
                        child: InkWell(
                          onTap: () => ref.read(navProvider.notifier).home(),
                          child: const Padding(padding: EdgeInsets.all(6), child: AppLogo(compact: true, size: 34)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final g in MenuGroup.values)
                        IconButton(
                          tooltip: groupLabel(t, g),
                          isSelected: !nav.myPage && nav.group == g,
                          style: IconButton.styleFrom(
                            backgroundColor: !nav.myPage && nav.group == g ? AppColors.primary : null,
                            foregroundColor: !nav.myPage && nav.group == g ? Colors.white : AppColors.ink,
                          ),
                          onPressed: () => ref.read(navProvider.notifier).group(g),
                          icon: Icon(groupIcon(g)),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: AppColors.paper,
                        border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2)),
                      ),
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
