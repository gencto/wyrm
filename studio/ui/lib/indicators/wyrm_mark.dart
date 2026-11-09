import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/motion.dart';

/// The large WYRM mark of the log-in hero, 220 × 130
/// (docs/design/specs/login.md §4.3).
///
/// - The spine `M20 85 C45 50 65 45 70 45 S105 25 115 30 S155 40 165 55
///   S190 95 200 100`, `emberLine` 2, round caps, is drawn once on open from
///   nothing: the board's `stroke-dasharray: 420` with the offset going
///   420 → 0 over 1.6 s `ease-out`, so 420·t of it shows.
/// - Five circles (20,85 r14) (65,45 r17) (115,30 r20, filled) (165,55 r17)
///   (200,100 r14), rings of 5 in ember on `ground0`, breathe: scale
///   1 → 1.18 → 1 and opacity 0.9 → 1 → 0.9 about their centres every 3.2 s,
///   `ease-in-out` per half, each 0.25 s after the one before.
///
/// Under reduced motion the spine is whole and the circles at rest (scale 1,
/// full opacity), as the board's `animation: none` leaves them.
class WyrmMark extends StatefulWidget {
  const WyrmMark({super.key});

  static const size = Size(220, 130);

  @override
  State<WyrmMark> createState() => _WyrmMarkState();
}

class _WyrmMarkState extends State<WyrmMark> with TickerProviderStateMixin {
  late final _spine = AnimationController(vsync: this, duration: Motion.spine);
  late final _breathe = AnimationController(
    vsync: this,
    duration: Motion.breathe,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _spine
        ..stop()
        ..value = 1;
      _breathe.stop();
    } else {
      if (_spine.isDismissed) {
        unawaited(_spine.forward());
      }
      if (!_breathe.isAnimating) {
        unawaited(_breathe.repeat());
      }
    }
  }

  @override
  void dispose() {
    _spine.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      size: WyrmMark.size,
      painter: _Mark(
        spine: CurvedAnimation(parent: _spine, curve: Curves.easeOut),
        breathe: _breathe,
        still: reduceMotion(context),
        line: c.emberLine,
        ember: c.ember,
        ground: c.ground0,
      ),
    );
  }
}

class _Mark extends CustomPainter {
  _Mark({
    required this.spine,
    required this.breathe,
    required this.still,
    required this.line,
    required this.ember,
    required this.ground,
  }) : super(repaint: Listenable.merge([spine, breathe]));

  final Animation<double> spine;
  final Animation<double> breathe;
  final bool still;
  final Color line;
  final Color ember;
  final Color ground;

  static final _path = Path()
    ..moveTo(20, 85)
    ..cubicTo(45, 50, 65, 45, 70, 45)
    // S x2 y2 x y: the first control point mirrors the previous second one.
    ..cubicTo(75, 45, 105, 25, 115, 30)
    ..cubicTo(125, 35, 155, 40, 165, 55)
    ..cubicTo(175, 70, 190, 95, 200, 100);

  static const _circles = [
    (Offset(20, 85), 14.0),
    (Offset(65, 45), 17.0),
    (Offset(115, 30), 20.0),
    (Offset(165, 55), 17.0),
    (Offset(200, 100), 14.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = 420 * spine.value;
    final stroke = Paint()
      ..color = line
      ..style = .stroke
      ..strokeWidth = 2
      ..strokeCap = .round;
    for (final metric in _path.computeMetrics()) {
      if (drawn > 0) {
        canvas.drawPath(metric.extractPath(0, drawn), stroke);
      }
    }
    for (final (i, (centre, r)) in _circles.indexed) {
      final phase = still
          ? null
          : loopPhase(
              breathe.value,
              Motion.breathe,
              const Duration(milliseconds: 250) * i,
            );
      final scale = phase == null
          ? 1.0
          : keyframes(phase, const [(0, 1), (.5, 1.18), (1, 1)]);
      final opacity = phase == null
          ? 1.0
          : keyframes(phase, const [(0, .9), (.5, 1), (1, .9)]);
      // The board fades the circle as one element: fill and ring together.
      canvas
        ..saveLayer(
          Rect.fromCircle(center: centre, radius: r * 1.2 + 3),
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
        )
        ..translate(centre.dx, centre.dy)
        ..scale(scale);
      if (i == 2) {
        canvas.drawCircle(.zero, r, Paint()..color = ember);
      } else {
        canvas
          ..drawCircle(.zero, r, Paint()..color = ground)
          ..drawCircle(
            .zero,
            r,
            Paint()
              ..color = ember
              ..style = .stroke
              ..strokeWidth = 5,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Mark old) =>
      old.still != still ||
      old.line != line ||
      old.ember != ember ||
      old.ground != ground;
}
