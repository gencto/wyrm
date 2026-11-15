import 'package:models/history_call.dart';
import 'package:models/watch_group.dart';

import '../redux/app_state.dart';

/// The historian's own values (`sys/history/*`), live while History
/// follows them: its size in MiB (its text when that is not a number), its
/// series, the days raw rows are kept, the rows written, the oldest day.
final class HistorianStats {
  const HistorianStats({
    this.sizeMib,
    this.size,
    this.series,
    this.keepDays,
    this.rowsWritten,
    this.oldestDay,
  });

  final num? sizeMib;
  final String? size;
  final String? series;
  final String? keepDays;
  final String? rowsWritten;
  final String? oldestDay;
}

/// What History shows of the historian, from the state.
final class _Historian with Selectors {
  _Historian(this.state);

  @override
  final AppState state;

  HistorianStats get historianStats {
    final s = historian.shownStats;
    final size = s['database_size'];
    return HistorianStats(
      sizeMib: size == null ? null : num.tryParse(size),
      size: size,
      series: s['series'],
      keepDays: s['retention_days'],
      rowsWritten: s['rows_written'],
      oldestDay: s['oldest_day'],
    );
  }

  /// The group picked, live.
  WatchGroup? get shownGroup => historian.shownGroups
      .where((g) => g.name == historian.selected)
      .firstOrNull;

  /// The watch of the one point picked (Stop recording works on it); null
  /// unless exactly one point of the group picked is.
  String? get pickedWatch {
    final g = shownGroup;
    final points = historian.points;
    if (g == null || points.length != 1) {
      return null;
    }
    final i = g.keys.indexOf(points.first);
    return i < 0 || i >= g.watchIds.length ? null : g.watchIds[i];
  }

  /// The key of [node] for History's calls: `sys/history`, the group
  /// picked, or the watch of the one point picked.
  String historyKeyOf(HistoryNode node) {
    final base = '${site.root}/sys/history';
    return switch (node) {
      HistoryNode.historian => base,
      HistoryNode.group => '$base/${historian.selected}',
      HistoryNode.watch => '$base/${historian.selected}/$pickedWatch',
    };
  }
}

// What History shows of the historian, as functions of the state: the
// selectors of `SelectHistorian` call them.
HistorianStats historianStatsOf(AppState s) => _Historian(s).historianStats;

WatchGroup? shownGroupOf(AppState s) => _Historian(s).shownGroup;

String? pickedWatchOf(AppState s) => _Historian(s).pickedWatch;

String historyKeyOf(AppState s, HistoryNode node) =>
    _Historian(s).historyKeyOf(node);
