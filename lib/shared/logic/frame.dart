import 'dart:math' as math;
import 'dart:ui';

enum AppFrame { desktop, phoneLandscape, phonePortrait }

AppFrame frameOf(Size size) {
  if (size.width <= size.height) return AppFrame.phonePortrait;
  if (size.height < 600 || size.width < 820) return AppFrame.phoneLandscape;
  return AppFrame.desktop;
}

/// Keeps a floating box of [box] size fully inside [area].
Offset clampInside(Offset pos, Size box, Size area) {
  final maxX = math.max(0.0, area.width - box.width);
  final maxY = math.max(0.0, area.height - box.height);
  return Offset(pos.dx.clamp(0.0, maxX), pos.dy.clamp(0.0, maxY));
}
