import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import 'trend_chart.dart';

/// A trend of values that arrive live (no history behind them): it keeps
/// the last [keep] values of each series while it is on screen.
class LiveSparkline extends StatefulWidget {
  const LiveSparkline({
    required this.values,
    required this.labels,
    required this.empty,
    this.keep = 240,
    this.height = 160,
    super.key,
  });

  /// The latest value of each series (null when none yet).
  final List<double?> values;
  final List<String> labels;
  final String empty;
  final int keep;
  final double height;

  @override
  State<LiveSparkline> createState() => _LiveSparklineState();
}

class _LiveSparklineState extends State<LiveSparkline> {
  final _series = <List<(int, double)>>[];

  void _take() {
    final now = DateTime.now().millisecondsSinceEpoch;
    while (_series.length < widget.values.length) {
      _series.add([]);
    }
    for (final (i, v) in widget.values.indexed) {
      if (v == null) {
        continue;
      }
      final s = _series[i];
      if (s.isNotEmpty && now - s.last.$1 < 900) {
        continue;
      }
      s.add((now, v));
      if (s.length > widget.keep) {
        s.removeAt(0);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _take();
  }

  @override
  void didUpdateWidget(LiveSparkline old) {
    super.didUpdateWidget(old);
    _take();
  }

  @override
  Widget build(BuildContext context) {
    final t = _series.isEmpty || _series.first.isEmpty ? null : _series.first;
    String hm(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }

    return DefaultTextStyle.merge(
      style: TextStyle(color: context.colors.text3),
      child: TrendChart(
        height: widget.height,
        empty: widget.empty,
        timeLabels: t == null ? ('', '') : (hm(t.first.$1), hm(t.last.$1)),
        series: [
          for (final (i, s) in _series.indexed)
            TrendSeriesVm(
              label: i < widget.labels.length ? widget.labels[i] : '',
              points: List.of(s),
            ),
        ],
      ),
    );
  }
}
