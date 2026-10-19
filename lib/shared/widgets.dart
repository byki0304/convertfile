import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_text.dart';
import 'file_rules.dart';
import 'logic/frame.dart';
import 'state.dart';
import 'theme.dart';
import 'web/picked_file.dart';

/// Grid-paper workbench with soft watercolor washes in the corners.
class GridBackground extends StatelessWidget {
  const GridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter(), child: child);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);
    void wash(Offset c, double r, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.wash.withValues(alpha: alpha),
              AppColors.wash.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final m = math.max(size.width, size.height);
    wash(Offset(size.width * 0.08, size.height * 0.92), m * 0.45, 0.75);
    wash(Offset(size.width * 0.95, size.height * 0.12), m * 0.38, 0.6);
    wash(Offset(size.width * 0.55, size.height * 1.05), m * 0.3, 0.4);
    final p = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PaperCard extends StatelessWidget {
  const PaperCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = AppColors.paper});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    decoration: cardDecoration(color: color),
    padding: padding,
    child: child,
  );
}

/// Hand-drawn format mark: colored rounded card with the extension text. No image files.
class FormatCard extends StatelessWidget {
  const FormatCard(this.ext, {super.key, this.size = 40});

  final String ext;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = ext.toUpperCase();
    return Semantics(
      label: label,
      child: Container(
        width: size,
        height: size * 1.2,
        decoration: BoxDecoration(
          color: formatColor(ext),
          borderRadius: BorderRadius.circular(size * 0.22),
          border: Border.all(color: AppColors.ink, width: 1.6),
          boxShadow: const [BoxShadow(color: AppColors.ink, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

class FormatPill extends StatelessWidget {
  const FormatPill(this.label, {super.key, this.ext, this.onTap, this.trailing});

  final String label;
  final String? ext;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final color = formatColor(ext ?? extOf(label));
    return Material(
      color: color,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.ink, width: 1.2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 16, color: Colors.white)],
            ],
          ),
        ),
      ),
    );
  }
}

enum JobStatus { uploading, queued, running, done, failed }

class StatusPill extends ConsumerWidget {
  const StatusPill(this.status, {super.key, this.progress});

  final JobStatus status;
  final int? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final (label, color) = switch (status) {
      JobStatus.uploading => (t.uploading(progress ?? 0), AppColors.primary),
      JobStatus.queued => (t.statusQueued, AppColors.sub),
      JobStatus.running => (t.statusRunning, AppColors.primary),
      JobStatus.done => (t.statusDone, AppColors.ok),
      JobStatus.failed => (t.statusFailed, AppColors.danger),
    };
    final busy = status == JobStatus.running || status == JobStatus.uploading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        if (busy)
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: LinearProgressIndicator(
                value: status == JobStatus.uploading ? (progress ?? 0) / 100 : null,
                minHeight: 3,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------- Foldy ----------

enum FoldyPose { wave, run, point, head, logo, dizzy }

class Foldy extends StatelessWidget {
  const Foldy({super.key, this.pose = FoldyPose.point, this.size = 96});

  final FoldyPose pose;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size(size, size), painter: _FoldyPainter(pose)),
  );
}

class _FoldyPainter extends CustomPainter {
  _FoldyPainter(this.pose);

  final FoldyPose pose;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final stroke = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = pose == FoldyPose.dizzy ? AppColors.errorCard : Colors.white;
    final head = pose == FoldyPose.head || pose == FoldyPose.logo;
    final body = head ? Rect.fromLTWH(22 * s, 14 * s, 56 * s, 66 * s) : Rect.fromLTWH(26 * s, 8 * s, 48 * s, 62 * s);
    final arrow = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * s
      ..strokeCap = StrokeCap.round;
    if (pose == FoldyPose.logo) {
      final ring = Rect.fromCircle(center: Offset(50 * s, 50 * s), radius: 44 * s);
      canvas.drawArc(ring, math.pi * 0.62, math.pi * 1.55, false, arrow);
      final a = math.pi * 0.62 + math.pi * 1.55;
      final tip = Offset(50 * s + math.cos(a) * 44 * s, 50 * s + math.sin(a) * 44 * s);
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + 9 * s, tip.dy)
          ..lineTo(tip.dx - 5 * s, tip.dy - 8 * s)
          ..lineTo(tip.dx - 4 * s, tip.dy + 9 * s)
          ..close(),
        Paint()..color = AppColors.accent,
      );
    }
    final fold = 14 * s;
    final path = Path()
      ..moveTo(body.left + 6 * s, body.top)
      ..lineTo(body.right - fold, body.top)
      ..lineTo(body.right, body.top + fold)
      ..lineTo(body.right, body.bottom - 6 * s)
      ..quadraticBezierTo(body.right, body.bottom, body.right - 6 * s, body.bottom)
      ..lineTo(body.left + 6 * s, body.bottom)
      ..quadraticBezierTo(body.left, body.bottom, body.left, body.bottom - 6 * s)
      ..lineTo(body.left, body.top + 6 * s)
      ..quadraticBezierTo(body.left, body.top, body.left + 6 * s, body.top)
      ..close();
    if (!head) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(body.center.dx, 96 * s), width: body.width * 1.1, height: 6 * s),
        Paint()..color = AppColors.ink.withValues(alpha: 0.12),
      );
    }
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    final corner = Path()
      ..moveTo(body.right - fold, body.top)
      ..lineTo(body.right - fold, body.top + fold)
      ..lineTo(body.right, body.top + fold)
      ..close();
    canvas.drawPath(corner, Paint()..color = AppColors.sideSelected);
    canvas.drawPath(corner, stroke);

    final eyeY = body.top + body.height * 0.38;
    final eyeDx = body.width * 0.18;
    final cx = body.center.dx;
    if (pose == FoldyPose.dizzy) {
      for (final x in [cx - eyeDx, cx + eyeDx]) {
        canvas.drawLine(Offset(x - 4 * s, eyeY - 4 * s), Offset(x + 4 * s, eyeY + 4 * s), stroke);
        canvas.drawLine(Offset(x + 4 * s, eyeY - 4 * s), Offset(x - 4 * s, eyeY + 4 * s), stroke);
      }
    } else {
      final eye = Paint()..color = AppColors.ink;
      final glint = Paint()..color = Colors.white;
      for (final x in [cx - eyeDx, cx + eyeDx]) {
        canvas.drawCircle(Offset(x, eyeY), 4.2 * s, eye);
        canvas.drawCircle(Offset(x + 1.3 * s, eyeY - 1.4 * s), 1.3 * s, glint);
      }
      final cheek = Paint()..color = const Color(0xFFF7B7B0).withValues(alpha: 0.85);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - eyeDx - 4 * s, eyeY + 8 * s), width: 8 * s, height: 5 * s), cheek);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + eyeDx + 4 * s, eyeY + 8 * s), width: 8 * s, height: 5 * s), cheek);
    }
    final mouth = Rect.fromCenter(center: Offset(cx, eyeY + 7 * s), width: 10 * s, height: 7 * s);
    canvas.drawArc(mouth, 0.25, math.pi - 0.5, false, stroke);

    if (head) return;
    final armY = body.top + body.height * 0.62;
    switch (pose) {
      case FoldyPose.wave:
        canvas.drawLine(Offset(body.right, armY), Offset(body.right + 14 * s, armY - 22 * s), stroke);
        canvas.drawLine(Offset(body.left, armY), Offset(body.left - 10 * s, armY + 10 * s), stroke);
      case FoldyPose.point:
        canvas.drawLine(Offset(body.right, armY), Offset(body.right + 18 * s, armY + 4 * s), stroke);
        canvas.drawLine(Offset(body.left, armY), Offset(body.left - 10 * s, armY + 10 * s), stroke);
      case FoldyPose.run:
        canvas.drawLine(Offset(body.right, armY), Offset(body.right + 12 * s, armY - 10 * s), stroke);
        canvas.drawLine(Offset(body.left, armY), Offset(body.left - 12 * s, armY + 8 * s), stroke);
      case FoldyPose.dizzy:
        final star = Paint()..color = AppColors.accent;
        canvas.drawCircle(Offset(body.left - 6 * s, body.top + 4 * s), 3 * s, star);
        canvas.drawCircle(Offset(body.right + 6 * s, body.top + 10 * s), 3 * s, star);
        canvas.drawLine(Offset(body.left, armY), Offset(body.left - 10 * s, armY + 10 * s), stroke);
        canvas.drawLine(Offset(body.right, armY), Offset(body.right + 10 * s, armY + 10 * s), stroke);
      case FoldyPose.head:
      case FoldyPose.logo:
        break;
    }
    final legY = body.bottom;
    final run = pose == FoldyPose.run;
    canvas.drawLine(Offset(cx - 9 * s, legY), Offset(cx - (run ? 18 : 10) * s, 94 * s), stroke);
    canvas.drawLine(Offset(cx + 9 * s, legY), Offset(cx + (run ? 18 : 10) * s, 94 * s), stroke);
  }

  @override
  bool shouldRepaint(covariant _FoldyPainter oldDelegate) => oldDelegate.pose != pose;
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.compact = false, this.size = 36});

  final bool compact;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Foldy(pose: FoldyPose.logo, size: size),
      if (!compact) ...[
        const SizedBox(width: 6),
        Text(
          'ConvertFile',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink, fontSize: size * 0.6, letterSpacing: -0.3),
        ),
      ],
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.pose = FoldyPose.point});

  final String message;
  final FoldyPose pose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
    child: Column(
      children: [
        Foldy(pose: pose, size: 88),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Row that is collapsed by default. Phones expand with one tap, desktop with a double click.
/// Checking happens only through the checkbox.
class ExpandableRow extends ConsumerWidget {
  const ExpandableRow({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.header,
    required this.details,
    this.checked,
    this.onChecked,
    this.color = AppColors.paper,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget header;
  final Widget details;
  final bool? checked;
  final ValueChanged<bool>? onChecked;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    final desktop = frameOf(MediaQuery.sizeOf(context)) == AppFrame.desktop;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardDecoration(color: color),
      child: Semantics(
        expanded: expanded,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: desktop ? null : onToggle,
          onDoubleTap: desktop ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (checked != null)
                      Semantics(
                        label: t.select,
                        child: Checkbox(value: checked, onChanged: (v) => onChecked?.call(v ?? false)),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(child: header),
                    IconButton(
                      tooltip: t.expand,
                      icon: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more),
                      ),
                      onPressed: onToggle,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(padding: const EdgeInsets.fromLTRB(12, 6, 0, 4), child: details)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `전체 선택` when nothing is checked, `삭제` when something is.
class SelectionToggleButton extends ConsumerWidget {
  const SelectionToggleButton({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onDelete,
    this.busy = false,
  });

  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    if (selectedCount == 0) {
      return OutlinedButton(onPressed: busy ? null : onSelectAll, child: Text(t.selectAll));
    }
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
      onPressed: busy ? null : onDelete,
      child: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text('${t.delete} ($selectedCount)'),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, AppText t, String message, {String? confirmLabel, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel ?? t.confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

/// Rounded box with a dashed outline (upload and drop areas).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.active = false, this.radius = 14});

  final Widget child;
  final bool active;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedPainter(active: active, radius: radius),
    child: child,
  );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({required this.active, required this.radius});

  final bool active;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = active ? AppColors.aiBubble : AppColors.paper.withValues(alpha: 0.7));
    final paint = Paint()
      ..color = active ? AppColors.primary : AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.4 : 1.4;
    for (final metric in (Path()..addRRect(rrect.deflate(0.7))).computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.active != active || old.radius != radius;
}

/// Dashed "drag a file here or click" area shared by every upload screen; lights up while a file is dragged over the window.
class UploadDropZone extends ConsumerWidget {
  const UploadDropZone({super.key, required this.onTap, this.caption, this.compact = false, this.multiple = false});

  final VoidCallback? onTap;
  final String? caption;
  final bool compact;
  final bool multiple;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(textProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: fileDragActive,
      builder: (context, dragging, _) => Semantics(
        button: true,
        label: multiple ? t.s('파일 추가', 'Add files', 'ファイル追加') : t.s('파일 선택', 'Choose a file', 'ファイルを選択'),
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: DashedBox(
            active: dragging,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 14 : 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    dragging ? Icons.file_download_outlined : Icons.cloud_upload_outlined,
                    size: compact ? 28 : 36,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dragging
                              ? t.s('여기에 놓으세요', 'Drop it here', 'ここにドロップ')
                              : t.s('파일을 끌어다 놓거나 눌러서 선택하세요', 'Drag a file here or click to choose', 'ファイルをドラッグするか、クリックして選択'),
                          style: TextStyle(fontWeight: FontWeight.w800, color: dragging ? AppColors.primary : AppColors.ink),
                        ),
                        if (caption != null && !compact)
                          Text(caption!, maxLines: 2, style: const TextStyle(color: AppColors.sub, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speech bubble with a small tail on the left bottom (hint text next to Foldy).
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.child, this.tailRight = false});

  final Widget child;
  final bool tailRight;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BubblePainter(tailRight),
    child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 22), child: child),
  );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.tailRight);

  final bool tailRight;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height - 10), const Radius.circular(16));
    final tx = tailRight ? size.width - 36 : 28.0;
    final path = Path()
      ..addRRect(body)
      ..moveTo(tx, size.height - 11)
      ..lineTo(tx + (tailRight ? 14 : -6), size.height)
      ..lineTo(tx + (tailRight ? -4 : 16), size.height - 11)
      ..close();
    final merged = Path.combine(PathOperation.union, Path()..addRRect(body), path);
    canvas.drawShadow(merged, AppColors.ink.withValues(alpha: 0.4), 3, false);
    canvas.drawPath(merged, Paint()..color = AppColors.paper);
    canvas.drawPath(
      merged,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.tailRight != tailRight;
}

/// Preset pill with the yellow arrow badge.
class PresetPill extends StatelessWidget {
  const PresetPill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF8E6),
    shape: pillBorder,
    elevation: 0,
    child: InkWell(
      customBorder: pillBorder,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.ink),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Gradient tile used for 원본 → 결과 in route cards.
class FlowTile extends StatelessWidget {
  const FlowTile({super.key, required this.label, required this.caption, required this.colors, this.size = 64});

  final String label;
  final String caption;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size * 1.35,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: 0.18), offset: const Offset(0, 3), blurRadius: 8)],
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          Text(
            caption,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

const sourceGradient = [Color(0xFFF2994A), Color(0xFFE5484D), Color(0xFFD4589F)];
const resultGradient = [Color(0xFF2FA36B), Color(0xFF2F6FE4), Color(0xFF7B5CD6)];

/// Centers page content at the 1100 max width and scrolls the whole menu on short screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.maxWidth = AppDims.contentMax});

  final Widget child;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: padding,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}
