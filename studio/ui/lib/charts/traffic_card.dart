import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/pill_tabs.dart';
import '../containers/sys_tile.dart';
import '../indicators/code_text.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// What [TrafficCard] draws: the router's network rates over the time
/// Studio has sampled them.
final class TrafficCardVm extends Equatable {
  const TrafficCardVm({
    required this.title,
    required this.measures,
    required this.measure,
    required this.inKey,
    required this.outKey,
    required this.inNow,
    required this.outNow,
    required this.unit,
    required this.note,
    required this.empty,
    this.inLabel = 'in',
    this.outLabel = 'out',
    this.inSeries = const [],
    this.outSeries = const [],
    this.top,
    this.axis = const [],
    this.describe = '',
  });

  final String title;
  final List<PillTabVm> measures;
  final String measure;
  final String inLabel;
  final String outLabel;
  final String inKey;
  final String outKey;
  final String inNow;
  final String outNow;
  final String unit;

  /// The samples, oldest first, in the measure's unit.
  final List<double> inSeries;
  final List<double> outSeries;

  /// The value at the top of the chart; the largest sample plus a tenth
  /// when null.
  final double? top;

  /// The labels under the chart, spread from the first sample to the last.
  final List<String> axis;
  final String note;

  /// Shown instead of the lines before two samples (`Collecting…`).
  final String empty;

  /// The chart in words, for assistive technology.
  final String describe;

  @override
  List<Object?> get props => [
    title,
    measures,
    measure,
    inLabel,
    outLabel,
    inKey,
    outKey,
    inNow,
    outNow,
    unit,
    inSeries,
    outSeries,
    top,
    axis,
    note,
    empty,
    describe,
  ];
}

/// Board `System`, *Router traffic*: the measure switch, the two figures of
/// now with their keys, the two lines and the time axis.
class TrafficCard extends StatelessWidget {
  const TrafficCard({required this.vm, required this.onMeasure, super.key});

  final TrafficCardVm vm;
  final ValueChanged<String> onMeasure;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ready = vm.inSeries.length >= 2 && vm.outSeries.length >= 2;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vm.title,
                  style: const TextStyle(fontSize: 14, fontWeight: .w600),
                ),
              ),
              PillTabs(
                tabs: vm.measures,
                selected: vm.measure,
                onSelect: onMeasure,
                height: 30,
                fontSize: 12,
                inset: true,
              ),
            ],
          ),
          Wrap(
            spacing: 28,
            runSpacing: 8,
            children: [
              _now(c, c.good, vm.inLabel, vm.inKey, vm.inNow),
              _now(c, c.text4, vm.outLabel, vm.outKey, vm.outNow),
            ],
          ),
          SizedBox(
            height: 120,
            child: ready
                ? Semantics(
                    image: true,
                    label: vm.describe,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _Lines(
                        inSeries: vm.inSeries,
                        outSeries: vm.outSeries,
                        top: vm.top,
                        grid: c.ground3,
                        inColor: c.good,
                        outColor: c.text4,
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      vm.empty,
                      style: TextStyle(fontSize: 13, color: c.text4),
                    ),
                  ),
          ),
          if (vm.axis.isNotEmpty)
            Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                for (final a in vm.axis)
                  Flexible(
                    child: Text(
                      a,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: c.text4,
                      ),
                    ),
                  ),
              ],
            ),
          CodeText(
            vm.note,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.text4),
          ),
        ],
      ),
    );
  }

  Widget _now(AppColors c, Color line, String label, String key, String now) =>
      Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Row(
            mainAxisSize: .min,
            spacing: 8,
            children: [
              Container(width: 16, height: 2, color: line),
              Text.rich(
                TextSpan(
                  text: '$label · ',
                  children: [
                    TextSpan(
                      text: key,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: SysTile.keyColor(c),
                      ),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: 12, color: c.text3),
              ),
            ],
          ),
          Row(
            mainAxisSize: .min,
            crossAxisAlignment: .baseline,
            textBaseline: .alphabetic,
            spacing: 6,
            children: [
              Text(
                now,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 20,
                  color: c.text1,
                ),
              ),
              Text(vm.unit, style: TextStyle(fontSize: 12, color: c.text4)),
            ],
          ),
        ],
      );
}

class _Lines extends CustomPainter {
  const _Lines({
    required this.inSeries,
    required this.outSeries,
    required this.top,
    required this.grid,
    required this.inColor,
    required this.outColor,
  });

  final List<double> inSeries;
  final List<double> outSeries;
  final double? top;
  final Color grid;
  final Color inColor;
  final Color outColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = (size.height * f).roundToDouble() + 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    var hi = top ?? 0;
    if (top == null) {
      for (final v in [...inSeries, ...outSeries]) {
        if (v > hi) {
          hi = v;
        }
      }
      hi *= 1.1;
    }
    if (hi <= 0) {
      hi = 1;
    }
    void line(List<double> series, Color color, double width) {
      final path = Path();
      for (final (i, v) in series.indexed) {
        final x = size.width * i / (series.length - 1);
        final y = size.height * (1 - (v / hi).clamp(0, 1));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }

    line(outSeries, outColor, 1.6);
    line(inSeries, inColor, 2);
  }

  @override
  bool shouldRepaint(_Lines old) =>
      old.inSeries != inSeries ||
      old.outSeries != outSeries ||
      old.top != top ||
      old.grid != grid ||
      old.inColor != inColor ||
      old.outColor != outColor;
}
