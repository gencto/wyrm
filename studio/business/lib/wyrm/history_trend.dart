import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';

import '../redux/app_state.dart';
import 'history_steps.dart';
import 'trend_window.dart';

/// One picked point of History's trend: its rows (the window's finer rows
/// once they cover it), the range's rows for the brush, and what draws it.
final class HistorySeries {
  const HistorySeries({
    required this.key,
    required this.label,
    required this.unit,
    required this.decimals,
    required this.rows,
    required this.overview,
    this.low,
    this.high,
    this.hidden = false,
    this.locked = false,
  });

  final String key;

  /// The point's display name; empty when it has none.
  final String label;
  final String unit;
  final int decimals;
  final IList<HistPoint> rows;
  final IList<HistPoint> overview;

  /// The buckets' min and max (same times as [rows]) once read.
  final IList<HistPoint>? low;
  final IList<HistPoint>? high;
  final bool hidden;

  /// The viewer may not read the point (spec trend.md §6).
  final bool locked;

  /// The point's name: its key's last segment.
  String get name => key.split('/').last;
}

/// History's trend (spec trend.md §4), computed from the state: the range
/// read coarse in the brush (µs), the window from its finer rows once they
/// cover it, the step drawn (null: raw rows).
final class HistoryTrend {
  const HistoryTrend({
    required this.series,
    required this.rangeStart,
    required this.rangeEnd,
    required this.windowStart,
    required this.windowEnd,
    required this.step,
    required this.minWindow,
    required this.following,
    required this.loading,
    required this.refining,
  });

  final List<HistorySeries> series;
  final int rangeStart;
  final int rangeEnd;
  final int windowStart;
  final int windowEnd;
  final Duration? step;
  final int minWindow;
  final bool following;

  /// The range is read and nothing is drawn yet.
  final bool loading;

  /// The window's finer rows are read.
  final bool refining;
}

/// What History's trend is made of, from the state.
final class _Trend with Selectors {
  _Trend(this.state);

  @override
  final AppState state;

  /// The trend's range in µs: the span of `historian.range` up to the last
  /// read or the newest sample since, whichever is later (so the trend
  /// stays equal between dispatches and still follows new samples).
  TrendSpan get historyRange {
    final h = historian;
    final end = trendRangeEnd(h.seriesAt, [
      for (final s in h.series.values) s.lastOrNull?.time,
      h.detail?.to,
    ]);
    return TrendSpan(end - h.range.span.inMicroseconds, end);
  }

  /// The picked points as a trend; null while no group or no point is.
  HistoryTrend? get historyTrend {
    final h = historian;
    if (h.selected == null || h.points.isEmpty) {
      return null;
    }
    final TrendSpan(:start, :end) = historyRange;
    final span = h.range.span;
    final window = h.window;
    final we = window?.end?.microsecondsSinceEpoch ?? end;
    final ws = window == null ? start : we - window.span.inMicroseconds;
    final d = h.detail;
    final fine =
        window != null &&
        d != null &&
        detailCovers(
          from: d.from.microsecondsSinceEpoch,
          to: d.to.microsecondsSinceEpoch,
          start: ws,
          end: we,
          follows: window.end == null,
        );
    // `raw` is no step of [stepDuration]: the plot draws raw rows.
    final step = fine ? d.step : stepFor(span);
    final minStep = stepDuration(stepFor(span, raw: false))!;
    return HistoryTrend(
      series: [
        for (final k in h.points)
          () {
            final info = nodes.table[k];
            final meta = nodes.detail[k];
            final rows = h.series[k] ?? const IListConst([]);
            final plot = fine ? d.points[k] ?? rows : rows;
            return HistorySeries(
              key: k,
              label: meta?.display ?? info?.display ?? '',
              unit: meta?.unit ?? info?.unit ?? '',
              decimals: decimalsOf(
                plot,
                precision: int.tryParse(meta?.cfg['precision'] ?? ''),
              ),
              rows: plot,
              overview: rows,
              low: fine ? d.low[k] : h.low[k],
              high: fine ? d.high[k] : h.high[k],
              hidden: h.hidden.contains(k),
              locked: !site.mayRead(k),
            );
          }(),
      ],
      rangeStart: start,
      rangeEnd: end,
      windowStart: ws.clamp(start, end),
      windowEnd: we.clamp(start, end),
      step: stepDuration(step),
      minWindow: 12 * minStep.inMicroseconds,
      following: window?.end == null,
      loading: h.seriesLoading && h.series.isEmpty,
      refining: h.windowLoading,
    );
  }
}

// History's trend as functions of the state: the selectors of
// `SelectHistorian` call them.
TrendSpan historyRangeOf(AppState s) => _Trend(s).historyRange;

HistoryTrend? historyTrendOf(AppState s) => _Trend(s).historyTrend;
