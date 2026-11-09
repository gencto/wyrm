import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import 'arc_spinner.dart';

/// The live steps under the busy Log in button
/// (docs/design/specs/login.md §3.7) and of the welcome's preload (§5): the
/// done ones ticked in teal, the one running with an ember spinner in
/// `text1`, the waiting ones with a grey ring in `muted`. A [late] step —
/// passed, but not finished in time — keeps an open ring in `text4`: it
/// goes on after Studio opens.
class LoginSteps extends StatelessWidget {
  const LoginSteps({
    required this.steps,
    required this.current,
    this.late = const {},
    super.key,
  });

  /// The step labels, already resolved (`Reaching plant`, …).
  final List<String> steps;

  /// The running step, 0-based.
  final int current;

  /// Steps before [current] that did not finish in time or failed.
  final Set<int> late;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: .start,
      spacing: 6,
      children: [
        for (final (i, label) in steps.indexed)
          Row(
            spacing: 10,
            children: [
              SizedBox.square(
                dimension: 16,
                child: Center(
                  child: i < current && late.contains(i)
                      ? Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: .circle,
                            border: .all(color: c.text4, width: 1.5),
                          ),
                        )
                      : i < current
                      ? CustomPaint(
                          size: const Size.square(14),
                          painter: _Check(c.good),
                        )
                      : i == current
                      ? ArcSpinner(color: c.ember, size: 14, strokeWidth: 2.6)
                      // 6 inside a 1.5 border, as the board's content box.
                      : Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: .circle,
                            border: .all(color: c.muted, width: 1.5),
                          ),
                        ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: i < current
                      ? c.text3
                      : i == current
                      ? c.text1
                      : c.muted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// `M5 12l5 5 9-10` in a 24 × 24 box, stroke 2.6, round.
class _Check extends CustomPainter {
  _Check(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas
      ..save()
      ..scale(k)
      ..drawPath(
        Path()
          ..moveTo(5, 12)
          ..relativeLineTo(5, 5)
          ..relativeLineTo(9, -10),
        Paint()
          ..color = color
          ..style = .stroke
          ..strokeWidth = 2.6
          ..strokeCap = .round
          ..strokeJoin = .round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Check old) => old.color != color;
}
