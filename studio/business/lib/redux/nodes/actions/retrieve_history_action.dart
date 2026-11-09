import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/hist_point.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the recorded values of the point [key] over `nodes.historyRange`
/// (`1h`, `24h`, `7d`) into `nodes.history`. A point nobody records answers
/// no rows (a watch in `sys/history` records it).
class RetrieveHistoryAction extends Action with WaitingAction {
  RetrieveHistoryAction(this.key, {this.limit = 2000});

  final String key;
  final int limit;

  /// `1h` → one hour, `24h`, `7d`.
  static Duration span(String range) {
    final n = int.tryParse(range.substring(0, range.length - 1)) ?? 1;
    return switch (range[range.length - 1]) {
      'm' => Duration(minutes: n),
      'd' => Duration(days: n),
      _ => Duration(hours: n),
    };
  }

  @override
  Future<AppState> reduce() async {
    final from = DateTime.now().toUtc().subtract(span(nodes.historyRange));
    List<HistRow> rows;
    try {
      rows = await deps.wyrm.history(
        key,
        from: from.toIso8601String(),
        limit: limit,
      );
    } on WyrmException {
      rows = const [];
    }
    return state.copyWith.nodes(
      historyKey: key,
      history: [
        for (final r in rows)
          HistPoint(
            time: DateTime.fromMicrosecondsSinceEpoch(r.t, isUtc: true),
            value:
                number(r.v) ??
                switch (r.v) {
                  VBool(:final v) => v ? 1 : 0,
                  _ => null,
                },
            text: text(r.v) ?? '${toDart(r.v)}',
            quality: r.q?.wireName,
          ),
      ].lock,
    );
  }
}
