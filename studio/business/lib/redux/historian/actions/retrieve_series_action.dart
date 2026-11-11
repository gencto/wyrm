import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_history_action.dart';

/// Reads the recorded values of the points the user picked
/// (`historian.points`, at most three) over `historian.range`, aggregated to
/// about 300 points per key, all at once. Nothing is read while no point
/// is picked: opening History lists the groups only.
class RetrieveSeriesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final keys = historian.points;
    if (keys.isEmpty) {
      return state.copyWith.historian(series: const IMapConst({}));
    }
    final span = RetrieveHistoryAction.span(historian.range);
    final from = DateTime.now().toUtc().subtract(span);
    final window = '${(span.inSeconds / 300).ceil().clamp(1, 1 << 30)}s';
    Future<IList<HistPoint>> read(String key) async {
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
      return [
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

    final got = await Future.wait([for (final k in keys) read(k)]);
    // The user may have picked other points while these were read.
    final now = historian.points;
    return state.copyWith.historian(
      series: {
        for (final (i, k) in keys.indexed)
          if (now.contains(k)) k: got[i],
        for (final e in historian.series.entries)
          if (now.contains(e.key) && !keys.contains(e.key)) e.key: e.value,
      }.lock,
    );
  }
}
