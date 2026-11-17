import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/pill_tabs.dart';
import '../containers/sys_tile.dart';
import '../indicators/code_text.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'trend.dart';

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
    this.trend,
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

  /// The two lines over the ring of samples (live, spec trend.md §4);
  /// null before two samples.
  final TrendVm? trend;
  final String note;

  /// Shown instead of the lines before two samples (`Collecting…`).
  final String empty;

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
    trend,
    note,
    empty,
  ];
}

/// Board `System`, *Router traffic*: the measure switch, the two figures of
/// now with their keys, the two lines and the time axis.
class TrafficCard extends StatelessWidget {
  const TrafficCard({
    required this.vm,
    required this.onMeasure,
    this.onWindow,
    this.onFollow,
    this.onReset,
    super.key,
  });

  final TrafficCardVm vm;
  final ValueChanged<String> onMeasure;

  /// The trend's window (µs), `Follow now` and `Reset zoom`.
  final RangeChanged<int>? onWindow;
  final VoidCallback? onFollow;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
                  style: const TextStyle(
                    fontSize: FontSizes.lg,
                    fontWeight: .w600,
                  ),
                ),
              ),
              PillTabs(
                tabs: vm.measures,
                selected: vm.measure,
                onSelect: onMeasure,
                height: 30,
                fontSize: FontSizes.sm,
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
          if (vm.trend case final t?)
            Trend(
              vm: t,
              onWindow: onWindow ?? (_, _) {},
              onFollow: onFollow,
              onReset: onReset,
            )
          else
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  vm.empty,
                  style: TextStyle(fontSize: FontSizes.md, color: c.text4),
                ),
              ),
            ),
          CodeText(
            vm.note,
            style: TextStyle(
              fontSize: FontSizes.sm,
              height: LineHeights.body,
              color: c.text4,
            ),
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
                        fontSize: FontSizes.xs,
                        color: SysTile.keyColor(c),
                      ),
                    ),
                  ],
                ),
                style: TextStyle(fontSize: FontSizes.sm, color: c.text3),
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
              Text(
                vm.unit,
                style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
              ),
            ],
          ),
        ],
      );
}
