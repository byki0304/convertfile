import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/logic/frame.dart';
import '../../../shared/state.dart';
import '../../../shared/theme.dart';
import '../calc_keypad.dart';

Size popupSize(AppFrame frame) => frame == AppFrame.desktop ? const Size(260, 380) : const Size(220, 330);

/// Floating basic calculator above every menu. Keeps its value while menus change.
class PopupCalculatorLayer extends ConsumerStatefulWidget {
  const PopupCalculatorLayer({super.key, required this.frame, required this.area});

  final AppFrame frame;
  final Size area;

  @override
  ConsumerState<PopupCalculatorLayer> createState() => _PopupCalculatorLayerState();
}

class _PopupCalculatorLayerState extends ConsumerState<PopupCalculatorLayer> {
  Offset? _drag;
  final _focus = FocusNode(debugLabel: 'popupCalc');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popup = ref.watch(calcPopupProvider);
    final box = popupSize(widget.frame);
    final pos = clampInside(_drag ?? popup.positionFor(widget.frame), box, widget.area);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        ignoring: !popup.open,
        child: AnimatedScale(
          scale: popup.open ? 1 : 0.9,
          duration: const Duration(milliseconds: 180),
          child: AnimatedOpacity(
            opacity: popup.open ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: popup.open ? _panel(context, pos) : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, Offset pos) {
    final t = ref.watch(textProvider);
    final state = ref.watch(basicCalcProvider);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        final k = keyFromEvent(e);
        if (k == null) return KeyEventResult.ignored;
        applyCalcKey(ref, basicCalcProvider, k);
        return KeyEventResult.handled;
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: cardDecoration(lifted: true),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _focus.requestFocus(),
                onPanStart: (_) => _drag = pos,
                onPanUpdate: (d) => setState(() => _drag = (_drag ?? pos) + d.delta),
                onPanEnd: (_) {
                  final p = clampInside(_drag ?? pos, popupSize(widget.frame), widget.area);
                  ref.read(calcPopupProvider.notifier).move(widget.frame, p);
                  setState(() => _drag = null);
                },
                child: Row(
                  children: [
                    _HeadButton(label: t.calcOff, onTap: () => ref.read(calcPopupProvider.notifier).setOpen(false)),
                    const SizedBox(width: 4),
                    _HeadButton(
                      label: t.fullScreen,
                      onTap: () {
                        ref.read(calcPopupProvider.notifier).setOpen(false);
                        ref.read(navProvider.notifier).calc(CalcTab.basic);
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.calculator,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Icon(Icons.drag_indicator, size: 18, color: AppColors.sub),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              CalcDisplay(state: state, big: 26),
              const SizedBox(height: 6),
              Expanded(
                child: CalcKeypad(rows: basicKeys, gap: 4, onKey: (k) => applyCalcKey(ref, basicCalcProvider, k)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadButton extends StatelessWidget {
  const _HeadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: AppColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.ink, width: 1.1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    ),
  );
}
