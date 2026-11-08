import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// The WYRM mark (five beads, the middle one filled) and the wordmark.
class WyrmLogo extends StatelessWidget {
  const WyrmLogo({this.showStudio = true, super.key});

  /// Adds `Studio` after the wordmark.
  final bool showStudio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: .min,
      spacing: 10,
      children: [
        CustomPaint(size: const Size(44, 26), painter: _Beads(c.ember)),
        Text(
          'WYRM',
          style: wordmark(size: 16, color: c.text1).copyWith(
            letterSpacing: 1.28,
          ),
        ),
        if (showStudio)
          Text('Studio', style: TextStyle(fontSize: 14, color: c.text3)),
      ],
    );
  }
}

class _Beads extends CustomPainter {
  _Beads(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 2;
    canvas
      ..drawCircle(const Offset(4, 17), 3, ring)
      ..drawCircle(const Offset(13, 9), 3.5, ring)
      ..drawCircle(const Offset(23, 6), 4, Paint()..color = color)
      ..drawCircle(const Offset(33, 11), 3.5, ring)
      ..drawCircle(const Offset(40, 20), 3, ring);
  }

  @override
  bool shouldRepaint(_Beads old) => old.color != color;
}
