import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/logic/frame.dart';
import '../../../shared/state.dart';
import '../../../shared/widgets.dart';
import '../calc_keypad.dart';
import 'business_tab.dart';
import 'fx_tab.dart';

/// Menu 11. Basic / scientific / exchange / business.
class FullCalculator extends ConsumerStatefulWidget {
  const FullCalculator({super.key, required this.tab});

  final CalcTab tab;

  @override
  ConsumerState<FullCalculator> createState() => _FullCalculatorState();
}

class _FullCalculatorState extends ConsumerState<FullCalculator> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyHandoff());
  }

  void _applyHandoff() {
    final h = ref.read(calcHandoffProvider);
    if (h == null || h.tab != widget.tab) return;
    if (h.tab == CalcTab.basic || h.tab == CalcTab.scientific) {
      final p = h.tab == CalcTab.basic ? basicCalcProvider : sciCalcProvider;
      final n = ref.read(p.notifier)..clear();
      final input = h.input.replaceAll('*', '×').replaceAll('/', '÷').replaceAll(' ', '');
      for (final ch in RegExp(r'sin|cos|tan|log|ln|√|.').allMatches(input)) {
        n.input(ch.group(0)!);
      }
      final line = n.equals();
      if (line != null) ref.read(calcHistoryProvider.notifier).add(line);
      ref.read(calcHandoffProvider.notifier).set(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.tab) {
      CalcTab.basic => const _KeypadCalculator(scientific: false),
      CalcTab.scientific => const _KeypadCalculator(scientific: true),
      CalcTab.fx => const FxTab(),
      CalcTab.business => const BusinessTab(),
    };
  }
}

class _KeypadCalculator extends ConsumerStatefulWidget {
  const _KeypadCalculator({required this.scientific});

  final bool scientific;

  @override
  ConsumerState<_KeypadCalculator> createState() => _KeypadCalculatorState();
}

class _KeypadCalculatorState extends ConsumerState<_KeypadCalculator> {
  final _focus = FocusNode(debugLabel: 'fullCalc');

  NotifierProvider<CalcNotifier, CalcState> get _p => widget.scientific ? sciCalcProvider : basicCalcProvider;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(textProvider);
    final state = ref.watch(_p);
    final degrees = ref.read(_p.notifier).degrees;
    final desktop = frameOf(MediaQuery.sizeOf(context)) == AppFrame.desktop;
    final rows = widget.scientific ? [...scientificKeys, ...basicKeys] : basicKeys;
    final keypadHeight = widget.scientific ? 480.0 : 340.0;
    final calc = PaperCard(
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, e) {
          final k = keyFromEvent(e);
          if (k == null) return KeyEventResult.ignored;
          applyCalcKey(ref, _p, k);
          return KeyEventResult.handled;
        },
        child: Column(
          children: [
            CalcDisplay(state: state, big: 40, badge: widget.scientific ? (degrees ? 'DEG' : 'RAD') : null),
            const SizedBox(height: 10),
            SizedBox(
              height: keypadHeight,
              child: CalcKeypad(
                rows: rows,
                labelOverride: {'DEG': degrees ? 'DEG' : 'RAD', 'π': 'π', '^': 'xʸ'},
                onKey: (k) {
                  _focus.requestFocus();
                  applyCalcKey(ref, _p, k);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
    final history = PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionTitle(t.s('계산 기록', 'History', '計算履歴')), const CalcHistoryList()],
      ),
    );
    return PageBody(
      child: desktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: calc),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: history),
              ],
            )
          : Column(children: [calc, const SizedBox(height: 16), history]),
    );
  }
}
