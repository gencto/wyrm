import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:models/node_detail.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/history_steps.dart';
import '../../../wyrm/mappers/node_detail_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';
import 'load_trend_extremes_action.dart';

/// Reads the recorded values of the points the user picked
/// (`historian.points`, at most three) over `historian.range`: the trend's
/// coarse range, drawn in the brush and in the plot until a window is read
/// finer (spec trend.md §4; `LoadTrendRangeAction` there). At most 300
/// buckets of the finest step that fits ([stepFor]), raw rows for a range
/// up to 2 h (read as 1 min buckets when a key answers [rawLimit] rows).
/// The buckets' min and max follow ([LoadTrendExtremesAction]). Nothing is
/// read while no point is picked: opening History lists the groups only.
class RetrieveSeriesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    // A point the viewer may not read is never queried (spec trend.md §6).
    final keys = historian.points.where(site.mayRead).toList();
    if (keys.isEmpty) {
      return state.copyWith.historian(
        series: const IMapConst({}),
        low: const IMapConst({}),
        high: const IMapConst({}),
        detail: null,
      );
    }
    final span = RetrieveHistoryAction.span(historian.range);
    final from = DateTime.now().toUtc().subtract(span).toIso8601String();
    Future<IList<HistPoint>> read(String key, String? step) async {
      try {
        final rows = await deps.wyrm.history(
          key,
          from: from,
          agg: step == null ? null : 'avg',
          window: step,
          limit: step == null ? rawLimit : 1000,
        );
        return [for (final r in rows) histPoint(r)].lock;
      } on WyrmException {
        return const IListConst([]);
      }
    }

    var step = stepFor(span);
    var got = await Future.wait([for (final k in keys) read(k, step)]);
    if (step == null && got.any((s) => s.length >= rawLimit)) {
      step = stepFor(span, raw: false);
      got = await Future.wait([for (final k in keys) read(k, step)]);
    }
    // The unit, name and decimals of a point the Explorer never opened: its
    // `~meta`, read quietly (a failure only leaves them out).
    final metas = <String, NodeDetail>{};
    for (final k in keys) {
      if (nodes.detail[k] == null) {
        try {
          metas[k] = nodeDetailOf(k, await deps.wyrm.meta(k));
        } on WyrmException {
          // The trend shows the point without a unit.
        }
      }
    }
    // The user may have picked other points while these were read.
    final now = historian.points;
    final withMeta = metas.isEmpty
        ? state
        : state.copyWith.nodes(detail: nodes.detail.addMap(metas));
    return withMeta.copyWith.historian(
      seriesAt: DateTime.now().toUtc(),
      series: {
        for (final (i, k) in keys.indexed)
          if (now.contains(k)) k: got[i],
        for (final e in historian.series.entries)
          if (now.contains(e.key) && !keys.contains(e.key)) e.key: e.value,
      }.lock,
    );
  }

  @override
  void after() {
    super.after();
    if (status.hasFinishedMethodReduce && historian.points.isNotEmpty) {
      unawaited(dispatchAndWait(LoadTrendExtremesAction(detail: false)));
    }
  }
}
