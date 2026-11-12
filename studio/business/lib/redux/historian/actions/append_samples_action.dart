import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:models/live_value.dart';

import '../../../wyrm/history_steps.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';

/// New samples of subscribed keys ([changed], one batch of
/// `LiveValuesService`) extend the trend of the points picked in History:
///
/// - only a picked point whose series was read, and only a sample newer
///   than its last point (the first sample of a subscription is the stored
///   value, which the read holds already);
/// - a sample in the same bucket as the last point (the read's step,
///   [stepFor] of the range) takes its place, a later one is a new point,
///   so the series stays about 300 points however long the tab is open;
///   raw rows (a range up to 2 h) keep every sample;
/// - points older than the range drop off;
/// - while the trend's window follows now, its finer rows grow the same
///   way at their own step (spec trend.md §7: the right edge follows);
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
    final bucket = stepDuration(stepFor(span))?.inMicroseconds;
    final series = _grow(historian.series, span, bucket);
    final d = historian.detail;
    final w = historian.window;
    final detail = d != null && w != null && w.end == null
        ? d.copyWith(
            points: _grow(
              d.points,
              span,
              stepDuration(d.step)?.inMicroseconds,
            ),
            to: DateTime.now().toUtc(),
          )
        : d;
    if (series == historian.series && detail?.points == d?.points) {
      return null;
    }
    return state.copyWith.historian(series: series, detail: detail);
  }

  IMap<String, IList<HistPoint>> _grow(
    IMap<String, IList<HistPoint>> of,
    Duration span,
    int? bucket,
  ) {
    var out = of;
    for (final k in historian.points) {
      final v = changed[k];
      final s = out[k];
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
        quality: bucket == null ? v.quality.name : null,
      );
      final last = s.lastOrNull;
      if (last != null && !point.time.isAfter(last.time)) {
        continue;
      }
      final from = point.time.subtract(span);
      var next = s.where((p) => !p.time.isBefore(from)).toIList();
      if (bucket != null) {
        int slot(HistPoint p) => p.time.microsecondsSinceEpoch ~/ bucket;
        if (next.lastOrNull case final l? when slot(l) == slot(point)) {
          next = next.removeLast();
        }
      }
      out = out.add(k, next.add(point));
    }
    return out;
  }
}
