import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../charts/trend.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'view_style.dart';

/// One line of a [ViewTrend]: the point's name and its value now.
final class ViewTrendSeriesVm extends Equatable {
  const ViewTrendSeriesVm({
    required this.name,
    required this.value,
    this.unit = '',
    this.decimals = 1,
    this.uncertain = false,
  });

  /// The key's last segments, in mono (`cpu/temp`).
  final String name;

  /// Null while the point has no value: a gap.
  final double? value;
  final String unit;
  final int decimals;
  final bool uncertain;

  @override
  List<Object?> get props => [name, value, unit, decimals, uncertain];
}

/// What [ViewTrend] draws.
final class ViewTrendVm extends Equatable {
  const ViewTrendVm({
    required this.title,
    required this.range,
    required this.series,
  });

  final String title;

  /// How far back the plot goes.
  final Duration range;
  final List<ViewTrendSeriesVm> series;

  @override
  List<Object?> get props => [title, range, series];
}

/// The `Trend` part of a view: Studio's own [Trend] over the values the
/// surface has seen since it was opened (one sample a second, kept for the
/// range). The history before that is not read in the prototype.
class ViewTrend extends StatefulWidget {
  const ViewTrend({required this.vm, this.now = DateTime.now, super.key});

  final ViewTrendVm vm;

  /// The clock (tests pass their own).
  final DateTime Function() now;

  @override
  State<ViewTrend> createState() => _ViewTrendState();
}

class _ViewTrendState extends State<ViewTrend> {
  final _rows = <String, List<TrendSample>>{};
  final _hidden = <String>{};
  Timer? _timer;
  (int, int)? _window;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(_sample);
    });
  }

  void _sample() {
    final t = widget.now().toUtc().microsecondsSinceEpoch;
    final from = t - widget.vm.range.inMicroseconds;
    for (final s in widget.vm.series) {
      final rows = _rows.putIfAbsent(s.name, () => []);
      if (rows.isNotEmpty && rows.last.t >= t) {
        continue;
      }
      rows
        ..add(
          TrendSample(
            t,
            s.value,
            q: s.value == null
                ? .bad
                : s.uncertain
                ? .uncertain
                : .good,
          ),
        )
        ..removeWhere((r) => r.t < from);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scope = ViewScope.of(context);
    final d = scope.density;
    final vm = widget.vm;
    final end = widget.now().toUtc().microsecondsSinceEpoch;
    var start = end - const Duration(seconds: 30).inMicroseconds;
    for (final rows in _rows.values) {
      if (rows.isNotEmpty && rows.first.t < start) {
        start = rows.first.t;
      }
    }
    final (ws, we) = _window ?? (start, end);
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: d.gap / 2,
      children: [
        if (vm.title.isNotEmpty)
          Text(
            vm.title,
            style: boardText(size: d.label + 1, weight: .w600, color: c.text1),
          ),
        Trend(
          vm: TrendVm(
            series: [
              for (final (i, s) in vm.series.indexed)
                TrendSeriesVm(
                  id: s.name,
                  name: s.name,
                  color: .byIndex(i),
                  unit: s.unit,
                  decimals: s.decimals,
                  samples: List.of(_rows[s.name] ?? const []),
                  overview: List.of(_rows[s.name] ?? const []),
                  hidden: _hidden.contains(s.name),
                ),
            ],
            rangeStart: start,
            rangeEnd: end,
            windowStart: ws.clamp(start, end),
            windowEnd: we.clamp(start, end),
            rollup: S.current.viewsLive,
            minWindow: const Duration(seconds: 10).inMicroseconds,
            endsNow: true,
            live: true,
            following: _window == null,
            card: false,
            hint: false,
            plotHeight: d == .desktop ? 180 : 200,
            format: scope.format,
          ),
          onWindow: (a, b) => setState(() => _window = (a, b)),
          onFollow: () => setState(() => _window = null),
          onReset: () => setState(() => _window = null),
          onSeriesToggle: (id) => setState(
            () => _hidden.contains(id) ? _hidden.remove(id) : _hidden.add(id),
          ),
        ),
      ],
    );
  }
}
