import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pages/app_shell.dart';
import '../../shared/api.dart';
import '../../shared/app_text.dart';
import '../../shared/errors.dart';
import '../../shared/file_rules.dart';
import '../../shared/state.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../calculator/full/fx_tab.dart';
import 'ai_home_state.dart';

TargetFormat? targetOfMenu(String menu) => menu.startsWith('to_') ? TargetFormat.fromExt(menu.substring(3)) : null;

CalcTab calcTabOf(String? mode) => CalcTab.values.firstWhere((c) => c.name == mode, orElse: () => CalcTab.basic);

String menuName(AppText t, String menu, {String? calcMode}) {
  final target = targetOfMenu(menu);
  if (target != null) return '${t.groupConvert} · ${formatTabLabel(t, target)}';
  return switch (menu) {
    'pdf_merge' => '${t.groupPdf} · ${t.tabMerge}',
    'pdf_edit' => '${t.groupPdf} · ${t.tabEdit}',
    'calculator' =>
      '${t.groupCalc} · ${switch (calcTabOf(calcMode)) {
        CalcTab.basic => t.tabBasic,
        CalcTab.scientific => t.tabScientific,
        CalcTab.fx => t.tabFx,
        CalcTab.business => t.tabBusiness,
      }}',
    _ => t.groupHome,
  };
}

/// Guidance card inside an AI bubble. Never switches menus by itself.
class RouteCard extends ConsumerStatefulWidget {
  const RouteCard({super.key, required this.turn});

  final Turn turn;

  @override
  ConsumerState<RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends ConsumerState<RouteCard> {
  bool _busy = false;

  Map<String, dynamic> get _card => widget.turn.routeCard!;

  Future<void> _goMenu() async {
    final menu = _card['targetMenu'] as String;
    final file = ref.read(turnFilesProvider)[widget.turn.id];
    final nav = ref.read(navProvider.notifier);
    final target = targetOfMenu(menu);
    if (target != null) {
      if (file != null) ref.read(convertHandoffProvider.notifier).set(ConvertHandoff(file, target));
      await nav.convert(target);
    } else if (menu == 'pdf_merge' || menu == 'pdf_edit') {
      final tab = menu == 'pdf_merge' ? PdfTab.merge : PdfTab.edit;
      if (file != null) ref.read(pdfHandoffProvider.notifier).set(PdfHandoff(tab: tab, file: file));
      await nav.pdf(tab);
    } else if (menu == 'calculator') {
      final tab = calcTabOf(_card['calcMode'] as String?);
      final currency = _card['fxCurrency'] as String?;
      ref
          .read(calcHandoffProvider.notifier)
          .set(
            CalcHandoff(tab: tab, input: _card['calcInput'] as String? ?? '', currency: fxCurrencies.contains(currency) ? currency : null),
          );
      await nav.calc(tab);
    }
  }

  /// Moves to the menu and starts converting the file already uploaded with this turn.
  Future<void> _convertNow() async {
    final t = ref.read(textProvider);
    final target = targetOfMenu(_card['targetMenu'] as String)!;
    setState(() => _busy = true);
    try {
      await Api.call('requestConversion', {
        'path': widget.turn.filePath,
        'name': widget.turn.fileName,
        'target': target.ext,
        'turnId': widget.turn.id,
      });
      await ref.read(navProvider.notifier).convert(target);
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(
          context,
          errorMessage(t, e.code, guest: ref.read(isGuestProvider), target: target, ext: extOf(widget.turn.fileName ?? '')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final menu = _card['targetMenu'] as String? ?? 'general';
    final target = targetOfMenu(menu);
    final srcExt = _card['sourceExt'] as String? ?? (widget.turn.fileName == null ? null : extOf(widget.turn.fileName!));
    final canConvert = _card['canConvert'] == true && widget.turn.filePath != null;
    final name = menuName(t, menu, calcMode: _card['calcMode'] as String?);
    final dstExt = target?.ext ?? (menu.startsWith('pdf_') ? 'pdf' : 'calc');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (srcExt != null && srcExt.isNotEmpty) ...[
                FormatCard(srcExt, size: 30),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: AppColors.accent),
                ),
              ],
              FormatCard(dstExt == 'calc' ? 'calc' : dstExt, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (target != null && canConvert)
                FilledButton(onPressed: _busy ? null : _convertNow, child: Text(t.s('바로 변환', 'Convert now', '今すぐ変換'))),
              OutlinedButton(onPressed: _busy ? null : _goMenu, child: Text(t.s('메뉴로 이동', 'Go to menu', 'メニューへ移動'))),
            ],
          ),
        ],
      ),
    );
  }
}
