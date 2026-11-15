import 'package:business/wyrm/history_steps.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:models/hist_point.dart';
import 'package:models/quality.dart';
import 'package:ui/charts/trend.dart';

// Moved to where they belong; the connectors still find them here.
export 'package:business/wyrm/trend_window.dart'
    show trendRangeEnd, trendWindow;
export 'package:ui/charts/trend_format.dart' show trendFormat;

/// What the three trends of Studio (History, Explorer, System) share on the
/// connector side (spec trend.md §5): times in the viewer's zone and
/// language, rows as samples, and the words for what a plot draws.

/// `15 min avg`, `1 h avg`, `raw`.
String rollupText(String? step) {
  final s = S.current;
  final d = stepDuration(step);
  if (d == null) {
    return s.trendRaw;
  }
  final name = d.inDays >= 1 && d.inHours % 24 == 0
      ? s.trendStepDays('${d.inDays}')
      : d.inHours >= 1 && d.inMinutes % 60 == 0
      ? s.trendStepHours('${d.inHours}')
      : s.trendStepMinutes('${d.inMinutes}');
  return s.trendAvg(name);
}

TrendQuality _quality(Quality? q) => switch (q) {
  Quality.bad => .bad,
  Quality.uncertain => .uncertain,
  Quality.good || null => .good,
};

/// [rows] as samples, with the bucket's min and max from [low] and [high]
/// (same times) when they were read.
List<TrendSample> trendSamples(
  IList<HistPoint> rows, {
  IList<HistPoint>? low,
  IList<HistPoint>? high,
}) {
  final lo = {
    for (final p in low ?? const IListConst(<HistPoint>[])) p.time: p.value,
  };
  final hi = {
    for (final p in high ?? const IListConst(<HistPoint>[])) p.time: p.value,
  };
  return [
    for (final p in rows)
      TrendSample(
        p.time.microsecondsSinceEpoch,
        p.value?.toDouble(),
        q: _quality(p.quality),
        lo: lo[p.time]?.toDouble(),
        hi: hi[p.time]?.toDouble(),
      ),
  ];
}

/// The decimals to write values of [rows] with: the point's `precision`
/// when known, else 0 for whole numbers and 1 otherwise.
int trendDecimals(Iterable<HistPoint> rows, {Object? precision}) {
  final p = switch (precision) {
    final num n => n.toInt(),
    final String t => int.tryParse(t),
    _ => null,
  };
  if (p != null) {
    return p.clamp(0, 6);
  }
  for (final r in rows) {
    final v = r.value;
    if (v != null && v != v.roundToDouble()) {
      return 1;
    }
  }
  return 0;
}

/// The finer rows read for [from]…[to] (µs) cover the window
/// [start]…[end]: they start at most a minute after it and, unless the
/// window [follows] now (its rows grow with new samples), end at most a
/// minute before it.
bool detailCovers({
  required int from,
  required int to,
  required int start,
  required int end,
  required bool follows,
}) {
  const slack = 60 * 1000000;
  return from <= start + slack && (follows || to >= end - slack);
}
