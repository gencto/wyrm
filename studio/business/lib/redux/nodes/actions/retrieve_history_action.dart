import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/history_range.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/hist_point.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';

/// Reads the recorded values of the point [key] over [range] (by default
/// `nodes.historyRange`) into `nodes.history`. A point nobody records
/// answers no rows (a watch in `sys/history` records it).
class RetrieveHistoryAction extends Action with WaitingAction {
  RetrieveHistoryAction(this.key, {this.limit = 2000, this.range});

  final String key;
  final int limit;

  /// The span read; null: the one on screen.
  final HistoryRange? range;

  /// History's ranges by name (`historian.range`): `1h` → one hour, `24h`,
  /// `7d`, `15m`.
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
    final from = DateTime.now().toUtc().subtract(
      (range ?? nodes.historyRange).span,
    );
    List<HistRow> rows;
    String? failed;
    try {
      rows = await deps.wyrm.history(
        key,
        from: from.toIso8601String(),
        limit: limit,
      );
    } on WyrmException catch (e) {
      // Nobody waits on a dialog for a chart: the panel says `history
      // unavailable` and the failure is a quiet line in Problems
      // (docs/design/specs/errors.md §4).
      rows = const [];
      failed = e.status.name;
      dispatchSync(
        AddProblemAction(
          refusalOf(e, key: key, call: 'history').copyWith(
            quiet: true,
            retry: () => RetrieveHistoryAction(key, limit: limit, range: range),
          ),
        ),
      );
    }
    return state.copyWith.nodes(
      historyKey: key,
      historyAt: DateTime.now().toUtc(),
      // Another point starts on its whole range.
      historyWindow: key == nodes.historyKey ? nodes.historyWindow : null,
      historyFailed: failed,
      history: [for (final r in rows) histPointOf(r, wholeText: true)].lock,
    );
  }
}
