import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/state.dart';
import '../../shared/theme.dart';

const basicKeys = [
  ['C', '⌫', '%', '÷'],
  ['7', '8', '9', '×'],
  ['4', '5', '6', '-'],
  ['1', '2', '3', '+'],
  ['(', '0', '.', '='],
];

const scientificKeys = [
  ['sin', 'cos', 'tan', 'DEG'],
  ['log', 'ln', '√', '^'],
  ['π', 'e', '(', ')'],
];

/// Applies a key to a calculator; returns a history line when = produced a result.
String? applyCalcKey(WidgetRef ref, NotifierProvider<CalcNotifier, CalcState> p, String key) {
  final n = ref.read(p.notifier);
  switch (key) {
    case 'C':
      n.clear();
    case '⌫':
      n.backspace();
    case '=':
      final line = n.equals();
      if (line != null) ref.read(calcHistoryProvider.notifier).add(line);
      return line;
    case 'DEG':
    case 'RAD':
      n.toggleDegrees();
    default:
      n.input(key);
  }
  return null;
}

/// Maps hardware keys to calculator keys.
String? keyFromEvent(KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return null;
  final k = e.logicalKey;
  if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) return '=';
  if (k == LogicalKeyboardKey.backspace) return '⌫';
  if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.delete) return 'C';
  final c = e.character;
  if (c == null) return null;
  if (RegExp(r'^[0-9.()%^]$').hasMatch(c)) return c;
  return switch (c) {
    '+' => '+',
    '-' => '-',
    '*' || 'x' => '×',
    '/' => '÷',
    '=' => '=',
    _ => null,
  };
}

class CalcDisplay extends StatelessWidget {
  const CalcDisplay({super.key, required this.state, this.big = 32, this.badge});

  final CalcState state;
  final double big;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.aiBubble,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              if (badge != null)
                Text(
                  badge!,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              const Spacer(),
              Flexible(
                child: Text(
                  state.evaluated ? state.expr : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.sub, fontSize: 13),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              state.display,
              maxLines: 1,
              style: TextStyle(fontSize: big, fontWeight: FontWeight.w800, color: state.error ? AppColors.danger : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class CalcKeypad extends StatelessWidget {
  const CalcKeypad({super.key, required this.rows, required this.onKey, this.labelOverride = const {}, this.gap = 6});

  final List<List<String>> rows;
  final ValueChanged<String> onKey;
  final Map<String, String> labelOverride;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: gap / 2),
                        child: _Key(label: labelOverride[k] ?? k, onTap: () => onKey(k), accent: k == '='),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.accent = false});

  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final op = '÷×-+%^'.contains(label) && label.length == 1;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: accent ? AppColors.primary : (op ? AppColors.aiBubble : AppColors.paper),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.ink, width: 1.2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: accent ? Colors.white : AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CalcHistoryList extends ConsumerWidget {
  const CalcHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final items = ref.watch(calcHistoryProvider);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(t.calcHistoryEmpty, style: const TextStyle(color: AppColors.sub)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in items)
          InkWell(
            onTap: () => ref.read(basicCalcProvider.notifier).setValue(line.split(' = ').last),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(line, textAlign: TextAlign.right),
            ),
          ),
      ],
    );
  }
}
