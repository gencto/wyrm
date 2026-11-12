import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/history_steps.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';

/// Reads the min and max of every bucket of the trend (`agg=min` and
/// `agg=max` with the same `window`, both at once per key) for the tooltip
/// (spec trend.md §4): of the coarse range, or of the window read finer
/// ([detail]). Raw rows have none. An answer for a range, a window or
/// points that changed meanwhile is dropped.
class LoadTrendExtremesAction extends Action {
  LoadTrendExtremesAction({required this.detail});

  /// The window's rows (`historian.detail`), else the range's.
  final bool detail;

  @override
  Future<AppState?> reduce() async {
    // A point the viewer may not read is never queried (spec trend.md §6).
    final keys = historian.points.where(site.mayRead).toList();
    final picked = historian.points;
    final d = historian.detail;
    final gen = historian.trendGen;
    final String? step;
    final String from;
    final String to;
    if (detail) {
      if (d == null) {
        return null;
      }
      step = d.step == 'raw' ? null : d.step;
      from = d.from.toIso8601String();
      to = d.to.toIso8601String();
    } else {
      final span = RetrieveHistoryAction.span(historian.range);
      step = stepFor(span);
      from = DateTime.now().toUtc().subtract(span).toIso8601String();
      to = '';
    }
    if (step == null || keys.isEmpty) {
      return null;
    }
    Future<IList<HistPoint>> read(String key, String agg) async {
      try {
        final rows = await deps.wyrm.history(
          key,
          from: from,
          to: to,
          agg: agg,
          window: step,
          limit: 1000,
        );
        return [for (final r in rows) histPoint(r)].lock;
      } on WyrmException {
        return const IListConst([]);
      }
    }

    final got = await Future.wait([
      for (final k in keys) ...[read(k, 'min'), read(k, 'max')],
    ]);
    if (historian.trendGen != gen || historian.points != picked) {
      return null;
    }
    final low = {for (final (i, k) in keys.indexed) k: got[2 * i]}.lock;
    final high = {for (final (i, k) in keys.indexed) k: got[2 * i + 1]}.lock;
    if (detail) {
      final now = historian.detail;
      if (now == null || now != d) {
        return null;
      }
      return state.copyWith.historian(
        detail: now.copyWith(low: low, high: high),
      );
    }
    return state.copyWith.historian(low: low, high: high);
  }
}
