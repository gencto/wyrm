import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// The WYRM mark (five beads, the middle one filled) and the wordmark.
class WyrmLogo extends StatelessWidget {
  const WyrmLogo({this.showStudio = true, this.large = false, super.key});

  /// Adds `Studio` after the wordmark.
  final bool showStudio;

  /// The log-in hero's size (docs/design/specs/login.md §2): wordmark 18
  /// spaced 0.08 em, `Studio` 15, 12 apart.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: .min,
      spacing: large ? 12 : 10,
      children: [
        CustomPaint(size: const Size(44, 26), painter: _Beads(c.ember)),
        Text(
          'WYRM',
          style: wordmark(size: large ? 18 : 16, color: c.text1).copyWith(
            letterSpacing: large ? 1.44 : 1.28,
          ),
        ),
        if (showStudio)
          Text(
            'Studio',
            style: TextStyle(fontSize: large ? 15 : 14, color: c.text3),
          ),
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
