// Canvas data, kept as the board writes it.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:ui/charts/trend.dart';

// The data of board `Trend` (design canvas, `canvas/Trend.dc.html`): 24 h
// of 5-minute buckets from Wed 11 Nov 2026 03:55, t1 and t2 with min and
// max, no rows 13:10–13:50 (comm fail), t2 uncertain 23:05–23:25. The
// frames `TrendHover`, `TrendZoomed`, `TrendPinned`, `TrendGap` are the
// board's `initial()` states.

const _n = 288;
const _stepMin = 5;
const int _startMin = 3 * 60 + 55;
const _gap = (111, 119);
const _unc = (230, 234);

/// 2026-11-11 00:00 UTC in µs.
final int _day0 = DateTime.utc(2026, 11, 11).microsecondsSinceEpoch;
const int _minute = 60 * 1000000;

/// The time of bucket [i].
int bucketAt(int i) => _day0 + (_startMin + i * _stepMin) * _minute;

({List<TrendSample> t1, List<TrendSample> t2}) _data() {
  final t1 = <TrendSample>[];
  final t2 = <TrendSample>[];
  for (var i = 0; i < _n; i++) {
    final h = (_startMin + i * _stepMin) / 60;
    final day = math.sin((h - 8) / 24 * math.pi * 2);
    final n1 = math.sin(i * 1.7) * 0.35 + math.sin(i * 0.37) * 0.6;
    final n2 = math.sin(i * 1.3 + 1) * 0.3 + math.sin(i * 0.29) * 0.5;
    final inGap = i >= _gap.$1 && i <= _gap.$2;
    if (inGap) {
      // Recorded, quality bad: the historian knows why there is no line.
      t1.add(TrendSample(bucketAt(i), null, q: .bad));
      t2.add(TrendSample(bucketAt(i), null, q: .bad));
      continue;
    }
    final v1 = 81 + day * 3.2 + n1 + (i > 150 && i < 170 ? 2.4 : 0);
    final v2 = 63 + day * 2.1 + n2;
    t1.add(
      TrendSample(
        bucketAt(i),
        v1,
        lo: v1 - 0.4 - n1.abs() * 0.3,
        hi: v1 + 0.5 + n2.abs() * 0.3,
      ),
    );
    t2.add(
      TrendSample(
        bucketAt(i),
        v2,
        q: i >= _unc.$1 && i <= _unc.$2 ? .uncertain : .good,
        lo: v2 - 0.3,
        hi: v2 + 0.4,
      ),
    );
  }
  return (t1: t1, t2: t2);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
String _two(int n) => n.toString().padLeft(2, '0');

/// The board's clock: UTC, so a frame draws the same everywhere.
final trendFormat = TrendFormat(
  locale: 'en UTC',
  clock: (t) => '${_two(t.hour)}:${_two(t.minute)}',
  clockSeconds: (t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}',
  day: (t) => '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}',
  weekday: (t) => _weekdays[t.weekday - 1],
);

/// One frame of the board: the window `a`…`b` (fractions of the range),
/// the crosshair at `hover` of the window, marker A at `pin` of the range.
final class TrendFrame {
  const TrendFrame({
    required this.vm,
    this.hover,
    this.marker,
  });

  final TrendVm vm;
  final int? hover;
  final int? marker;
}

TrendFrame trendFrame(
  String start, {
  Set<String> hidden = const {},
  bool loading = false,
  bool refining = false,
  bool empty = false,
}) {
  final (a, b, hover, pin) = switch (start) {
    'zoomed' => (0.36, 0.5, 0.55, null),
    'pinned' => (0.3, 0.75, 0.72, 0.36),
    'hover' => (0.0, 1.0, 0.62, null),
    'gap' => (0.3, 0.5, 0.43, null),
    _ => (0.0, 1.0, null, null),
  };
  final i0 = (a * (_n - 1)).floor();
  final i1 = math.max(i0 + 2, (b * (_n - 1)).ceil());
  final span = i1 - i0;
  final d = _data();
  final series = [
    TrendSeriesVm(
      id: 't1',
      name: 't1',
      label: 'Supply temp',
      color: .ember,
      unit: '°C',
      samples: empty ? const [] : d.t1,
      overview: empty ? const [] : d.t1,
      hidden: hidden.contains('t1'),
      gapReason: 'comm_fail · device not reachable',
    ),
    TrendSeriesVm(
      id: 't2',
      name: 't2',
      label: 'Return temp',
      color: .good,
      unit: '°C',
      samples: empty ? const [] : d.t2,
      overview: empty ? const [] : d.t2,
      hidden: hidden.contains('t2'),
      gapReason: 'comm_fail · device not reachable',
    ),
  ];
  return TrendFrame(
    vm: TrendVm(
      title: 'Supply and return temperature',
      series: series,
      rangeStart: bucketAt(0),
      rangeEnd: bucketAt(_n - 1),
      windowStart: bucketAt(i0),
      windowEnd: bucketAt(i1),
      // The board's words: `15 min avg` over more than 12 h, else `5 min`.
      rollup: span * _stepMin > 12 * 60 ? '15 min avg' : '5 min avg',
      step: _stepMin * _minute,
      minWindow: 12 * _stepMin * _minute,
      endsNow: true,
      loading: loading,
      refining: refining,
      format: trendFormat,
    ),
    hover: hover == null ? null : bucketAt((i0 + hover * span).round()),
    marker: pin == null ? null : bucketAt((pin * (_n - 1)).round()),
  );
}

/// The board's frame on a page as the canvas mounts it (`hint-size
/// 100%, 460px` on the workspace ground).
Widget trendBoard(
  TrendFrame f, {
  void Function(int, int)? onWindow,
  ValueChanged<String>? onToggle,
  VoidCallback? onReset,
}) => Builder(
  builder: (context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Align(
      alignment: .topCenter,
      child: Trend(
        vm: f.vm,
        initialHover: f.hover,
        initialMarker: f.marker,
        onWindow: onWindow ?? (_, _) {},
        onSeriesToggle: onToggle,
        onReset: onReset,
      ),
    ),
  ),
);
