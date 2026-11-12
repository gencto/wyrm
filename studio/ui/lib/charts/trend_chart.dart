import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One series of a trend: its points (time in ms since the epoch, value).
final class TrendSeriesVm extends Equatable {
  const TrendSeriesVm({required this.label, required this.points});

  final String label;
  final List<(int, double)> points;

  @override
  List<Object?> get props => [label, points];
}

/// A line chart over time (board *History · watch groups and trends*):
/// gridlines, the min and max on the left, the first and last time below,
/// each series a line, the first in teal.
class TrendChart extends StatelessWidget {
  const TrendChart({
    required this.series,
    required this.empty,
    this.timeLabels = const ('', ''),
    this.height = 220,
    super.key,
  });

  final List<TrendSeriesVm> series;

  /// Shown when there is nothing to draw.
  final String empty;

  /// The first and the last time, already formatted.
  final (String, String) timeLabels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pts = [for (final s in series) ...s.points];
    if (pts.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(empty, style: TextStyle(fontSize: 13, color: c.text4)),
        ),
      );
    }
    final lo = pts.map((p) => p.$2).reduce(math.min);
    final hi = pts.map((p) => p.$2).reduce(math.max);
    final colors = [c.good, c.ember, c.warn, c.bad, c.text2];
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  width: 56,
                  child: Column(
                    crossAxisAlignment: .end,
                    mainAxisAlignment: .spaceBetween,
                    children: [
                      Text(_n(hi), style: mono(size: 11, color: c.text4)),
                      Text(_n(lo), style: mono(size: 11, color: c.text4)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    painter: _TrendPainter(
                      series: series,
                      colors: colors,
                      grid: c.line1,
                      lo: lo,
                      hi: hi,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 64, top: 6),
            child: Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Text(timeLabels.$1, style: mono(size: 11, color: c.text4)),
                Text(timeLabels.$2, style: mono(size: 11, color: c.text4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.series,
    required this.colors,
    required this.grid,
    required this.lo,
    required this.hi,
  });

  final List<TrendSeriesVm> series;
  final List<Color> colors;
  final Color grid;
  final double lo;
  final double hi;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    final all = [for (final s in series) ...s.points];
    final t0 = all.map((p) => p.$1).reduce(math.min);
    final t1 = all.map((p) => p.$1).reduce(math.max);
    final span = (t1 - t0) == 0 ? 1 : t1 - t0;
    final range = (hi - lo) == 0 ? 1.0 : hi - lo;
    for (final (i, s) in series.indexed) {
      if (s.points.isEmpty) {
        continue;
      }
      final path = Path();
      for (final (j, (t, v)) in s.points.indexed) {
        final x = size.width * (t - t0) / span;
        final y = size.height - size.height * (v - lo) / range;
        j == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i % colors.length]
          ..style = .stroke
          ..strokeWidth = 1.8
          ..strokeJoin = .round,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.series != series || old.lo != lo || old.hi != hi;
}
