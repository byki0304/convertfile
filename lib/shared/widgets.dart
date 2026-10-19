import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_text.dart';
import 'file_rules.dart';
import 'logic/frame.dart';
import 'state.dart';
import 'theme.dart';

/// Light grid workbench background.
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
    final body = head ? Rect.fromLTWH(18 * s, 10 * s, 64 * s, 72 * s) : Rect.fromLTWH(26 * s, 8 * s, 48 * s, 62 * s);
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
    canvas.drawPath(path.shift(Offset(0, 3 * s)), Paint()..color = AppColors.ink);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    final corner = Path()
      ..moveTo(body.right - fold, body.top)
      ..lineTo(body.right - fold, body.top + fold)
      ..lineTo(body.right, body.top + fold);
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
      canvas.drawCircle(Offset(cx - eyeDx, eyeY), 4 * s, eye);
      canvas.drawCircle(Offset(cx + eyeDx, eyeY), 4 * s, eye);
    }
    final mouth = Rect.fromCenter(center: Offset(cx, eyeY + 10 * s), width: 12 * s, height: 8 * s);
    canvas.drawArc(mouth, 0.2, math.pi - 0.4, false, stroke);

    final arrow = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * s
      ..strokeCap = StrokeCap.round;
    final ac = Offset(cx, body.bottom - body.height * 0.22);
    final ar = body.width * 0.2;
    canvas.drawArc(Rect.fromCircle(center: ac, radius: ar), -math.pi * 0.1, math.pi * 1.5, false, arrow);
    final tip = ac + Offset(math.cos(-math.pi * 0.1) * ar, math.sin(-math.pi * 0.1) * ar);
    canvas.drawLine(tip, tip + Offset(-6 * s, -2 * s), arrow);
    canvas.drawLine(tip, tip + Offset(1 * s, -7 * s), arrow);

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
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink, fontSize: size * 0.55),
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

/// Centers page content at the 1100 max width and scrolls the whole menu on short screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: padding,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDims.contentMax),
        child: child,
      ),
    ),
  );
}
