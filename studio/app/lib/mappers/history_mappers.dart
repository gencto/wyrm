import 'package:business/wyrm/historian_stats.dart';
import 'package:business/wyrm/history_trend.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:models/history_call.dart';
import 'package:models/trend_range.dart';
import 'package:models/watch_group.dart';
import 'package:ui/charts/trend.dart';
import 'package:ui/pages/history_screen.dart';

import '../common/trend.dart';

/// History's range as its tab draws it.
extension TrendRangeSpan on TrendRange {
  HistorySpan get tab => switch (this) {
    TrendRange.hour => .hour,
    TrendRange.day => .day,
    TrendRange.week => .week,
    TrendRange.month => .month,
  };
}

/// A tab of History's trend as the range it reads.
extension HistorySpanRange on HistorySpan {
  TrendRange get range => switch (this) {
    HistorySpan.hour => .hour,
    HistorySpan.day => .day,
    HistorySpan.week => .week,
    HistorySpan.month => .month,
  };
}

/// A watch group as History draws it, with the rows read for each point
/// on the trend (`series`).
extension WatchGroupVmOf on WatchGroup {
  WatchGroupVm vm(IMap<String, IList<HistPoint>> series) => WatchGroupVm(
    name: name,
    logging: loggingType,
    interval: interval,
    flush: flush,
    points: [
      for (final (i, k) in keys.indexed)
        WatchPointVm(
          key: k,
          watch: i < watchIds.length ? watchIds[i] : '',
          rows: series[k]?.length,
        ),
    ],
  );
}

/// The historian's values as History draws them.
extension HistorianStatsVmOf on HistorianStats {
  HistorianStatsVm get vm => HistorianStatsVm(
    sizeMib: sizeMib,
    size: size,
    series: series,
    keepDays: keepDays,
    rowsWritten: rowsWritten,
    oldestDay: oldestDay,
  );
}

/// The picked points' trend as History's trend draws it.
extension HistoryTrendVmOf on HistoryTrend {
  HistoryTrendVm get vm => HistoryTrendVm(
    series: [
      for (final (i, s) in series.indexed)
        TrendSeriesVm(
          id: s.key,
          name: s.name,
          label: s.label,
          color: TrendColor.byIndex(i),
          unit: s.unit,
          decimals: s.decimals,
          samples: trendSamples(s.rows, low: s.low, high: s.high),
          overview: trendSamples(s.overview),
          hidden: s.hidden,
          locked: s.locked,
        ),
    ],
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    windowStart: windowStart,
    windowEnd: windowEnd,
    step: step,
    minWindow: minWindow,
    following: following,
    loading: loading,
    refining: refining,
  );
}

/// An action of History's screen as the call it makes on `sys/history`.
extension HistoryActCall on HistoryAct {
  HistoryCall get call => switch (this) {
    HistoryAct.addGroup => .addWatchGroup,
    HistoryAct.addPath => .addWatchPath,
    HistoryAct.edit => .edit,
    HistoryAct.purge => .purge,
    HistoryAct.remove => .remove,
    HistoryAct.unsubscribe => .unsubscribe,
  };
}
