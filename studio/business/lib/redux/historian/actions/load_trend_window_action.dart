import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_detail.dart';
import 'package:models/hist_point.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/history_steps.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'load_trend_extremes_action.dart';

/// Reads the picked points again for the trend's window only, finer than
/// the range (spec trend.md §4): about 300 buckets of the finest step that
/// fits, raw rows (with their quality) for a window up to 2 h unless a key
/// answers [rawLimit] rows. Runs 250 ms after the window stopped moving;
/// the coarse line stays meanwhile, and an answer a newer window, range or
/// pick superseded (`historian.trendGen`) is dropped. The window's min and
/// max follow ([LoadTrendExtremesAction]).
class LoadTrendWindowAction extends Action with Debounce, WaitingAction {
  @override
  int get debounce => 250; // milliseconds

  @override
  Future<AppState?> reduce() async {
    final w = historian.window;
    // A point the viewer may not read is never queried (spec trend.md §6).
    final keys = historian.points.where(site.mayRead).toList();
    if (w == null || keys.isEmpty) {
      return historian.detail == null
          ? null
          : state.copyWith.historian(detail: null);
    }
    final gen = historian.trendGen;
    final (from, to) = w.at(DateTime.now().toUtc());
    Future<IList<HistPoint>> read(String key, String? step) async {
      try {
        final rows = await deps.wyrm.history(
          key,
          from: from.toIso8601String(),
          // A window that follows now reads up to now.
          to: w.end == null ? '' : to.toIso8601String(),
          agg: step == null ? null : 'avg',
          window: step,
          limit: step == null ? rawLimit : 1000,
        );
        return [for (final r in rows) histPoint(r)].lock;
      } on WyrmException {
        return const IListConst([]);
      }
    }

    var step = stepFor(w.span);
    var got = await Future.wait([for (final k in keys) read(k, step)]);
    if (step == null && got.any((s) => s.length >= rawLimit)) {
      step = stepFor(w.span, raw: false);
      got = await Future.wait([for (final k in keys) read(k, step)]);
    }
    if (historian.trendGen != gen) {
      return null;
    }
    return state.copyWith.historian(
      detail: HistDetail(
        from: from,
        to: to,
        step: step ?? 'raw',
        points: {for (final (i, k) in keys.indexed) k: got[i]}.lock,
      ),
    );
  }

  @override
  void after() {
    super.after();
    if (status.hasFinishedMethodReduce &&
        (historian.detail?.step ?? 'raw') != 'raw') {
      unawaited(dispatchAndWait(LoadTrendExtremesAction(detail: true)));
    }
  }
}
