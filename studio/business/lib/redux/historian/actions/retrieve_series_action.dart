import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';

/// Reads the recorded values of every key of the selected watch group over
/// `historian.range`, aggregated to about 300 points per key.
class RetrieveSeriesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final g = historian.groups
        .where((g) => g.name == historian.selected)
        .firstOrNull;
    if (g == null) {
      return null;
    }
    final span = RetrieveHistoryAction.span(historian.range);
    final from = DateTime.now().toUtc().subtract(span);
    final window = '${(span.inSeconds / 300).ceil().clamp(1, 1 << 30)}s';
    final series = <String, IList<HistPoint>>{};
    for (final key in g.keys) {
      List<HistRow> rows;
      try {
        rows = await deps.wyrm.history(
          key,
          from: from.toIso8601String(),
          agg: 'avg',
          window: window,
          limit: 1000,
        );
      } on WyrmException {
        rows = const [];
      }
      series[key] = [
        for (final r in rows)
          HistPoint(
            time: DateTime.fromMicrosecondsSinceEpoch(r.t, isUtc: true),
            value:
                number(r.v) ??
                switch (r.v) {
                  VBool(:final v) => v ? 1 : 0,
                  _ => null,
                },
            text: text(r.v) ?? '',
            quality: r.q?.wireName,
          ),
      ].lock;
    }
    return state.copyWith.historian(series: series.lock);
  }
}
