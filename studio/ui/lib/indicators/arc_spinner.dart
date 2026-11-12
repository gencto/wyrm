import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/motion.dart';

/// The spinner of the log-in board (docs/design/specs/login.md §4.8): a 3/4
/// arc (`M12 3a9 9 0 1 0 9 9` in a 24 × 24 box) with round caps, turning once
/// every 0.9 s, linear. The gateway field shows it while the gateway is
/// checked (16, grey, 2.4); a log-in step shows it while it runs (14, ember,
/// 2.6). Under reduced motion it stops and becomes a static ring.
class ArcSpinner extends StatefulWidget {
  const ArcSpinner({
    required this.color,
    this.size = 16,
    this.strokeWidth = 2.4,
    this.label,
    super.key,
  });

  final Color color;

  /// The side of the square the 24 × 24 drawing is scaled into.
  final double size;

  /// In the 24 × 24 drawing's units, as the board writes it.
  final double strokeWidth;

  /// What is being waited for, for a screen reader.
  final String? label;

  @override
  State<ArcSpinner> createState() => _ArcSpinnerState();
}

class _ArcSpinnerState extends State<ArcSpinner>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: Motion.spin);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat().ignore();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return Semantics(
      label: widget.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _Arc(
            turn: _spin,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
            ring: still,
          ),
        ),
      ),
    );
  }
}

class _Arc extends CustomPainter {
  _Arc({
    required this.turn,
    required this.color,
    required this.strokeWidth,
    required this.ring,
  }) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;
  final double strokeWidth;
  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k);
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = .round;
    const circle = Rect.fromLTWH(3, 3, 18, 18);
    if (ring) {
      canvas.drawOval(circle, paint);
    } else {
      // From the top (−90°) counter-clockwise to the right (0°): three
      // quarters, the gap at the top right, turned by the controller.
      canvas
        ..translate(12, 12)
        ..rotate(turn.value * 2 * math.pi)
        ..translate(-12, -12)
        ..drawArc(circle, -math.pi / 2, -1.5 * math.pi, false, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Arc old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.ring != ring;
}
