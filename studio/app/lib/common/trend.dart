import 'package:business/wyrm/history_steps.dart';
// Moved to where they belong; the connectors still find them here.
import 'package:business/wyrm/trend_window.dart' show decimalsOf;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/charts/trend_format.dart' show trendRollup;

export 'package:business/wyrm/trend_window.dart'
    show detailCovers, trendRangeEnd, trendWindow;
export 'package:ui/charts/trend_format.dart' show trendFormat;

/// What the three trends of Studio (History, Explorer, System) share on the
/// connector side (spec trend.md §5): times in the viewer's zone and
/// language, rows as samples, and the words for what a plot draws.

/// `15 min avg`, `1 h avg`, `raw`: the words of [trendRollup] for a step's
/// name (`15m`).
String rollupText(String? step) => trendRollup(stepDuration(step));

TrendQuality _quality(String? q) => switch (q) {
  'bad' => .bad,
  'uncertain' => .uncertain,
  _ => .good,
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
/// when known (a number, or its text), else 0 for whole numbers and 1
/// otherwise.
int trendDecimals(Iterable<HistPoint> rows, {Object? precision}) => decimalsOf(
  rows,
  precision: switch (precision) {
    final num n => n.toInt(),
    final String t => int.tryParse(t),
    _ => null,
  },
);
