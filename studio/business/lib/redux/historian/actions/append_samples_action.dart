import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';

/// New samples of subscribed keys ([changed], one batch of
/// `LiveValuesService`) extend the trend of the points picked in History:
///
/// - only a picked point whose series was read, and only a sample newer
///   than its last point (the first sample of a subscription is the stored
///   value, which the read holds already);
/// - a sample in the same bucket as the last point (the read's bucket,
///   the range over 300) takes its place, a later one is a new point, so
///   the series stays about 300 points however long the tab is open;
/// - points older than the range drop off;
/// - a bool is 0/1 as in the read; a removed value adds nothing.
class AppendSamplesAction extends Action {
  AppendSamplesAction(this.changed);

  final Map<String, LiveValue?> changed;

  @override
  AppState? reduce() {
    if (historian.follow == null) {
      return null;
    }
    final span = RetrieveHistoryAction.span(historian.range);
    final bucket = (span.inMicroseconds / 300).ceil().clamp(1, 1 << 62);
    var series = historian.series;
    for (final k in historian.points) {
      final v = changed[k];
      final s = series[k];
      if (v == null || s == null) {
        continue;
      }
      final point = HistPoint(
        time: v.time.toUtc(),
        value: switch (v.value) {
          final num n => n,
          final bool b => b ? 1 : 0,
          _ => null,
        },
        text: '${v.value ?? ''}',
        quality: v.quality.name,
      );
      final last = s.lastOrNull;
      if (last != null && !point.time.isAfter(last.time)) {
        continue;
      }
      final from = point.time.subtract(span);
      var next = s.where((p) => !p.time.isBefore(from)).toIList();
      int slot(HistPoint p) => p.time.microsecondsSinceEpoch ~/ bucket;
      if (next.lastOrNull case final l? when slot(l) == slot(point)) {
        next = next.removeLast();
      }
      series = series.add(k, next.add(point));
    }
    return series == historian.series
        ? null
        : state.copyWith.historian(series: series);
  }
}
