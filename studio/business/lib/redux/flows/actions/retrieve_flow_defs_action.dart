import 'package:async_redux/async_redux.dart' show Store;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/flow_def.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../../wyrm/mappers/flow_value_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// What a flow's newest definition says for its row: the keys it reads
/// and writes, and its block count.
typedef FlowDefFacts = ({
  IList<String> reads,
  IList<String> writes,
  int blocks,
});

/// Reads, all at once, the newest definition (`dataflows/<id>` ▸
/// `history`) of the flows [ids]: a flow Flows has not seen, or one whose
/// `version` changed. A row's `version` is then the live one: the version
/// its reads, writes and blocks belong to.
///
/// Not a `WaitingAction` (a live change is not a refresh of the screen, so
/// no sweep bar). `ApplyFlowValuesAction` asks [reading] for each id, so a
/// version that arrives during the read does not read it twice. A flow
/// whose history the user may not read keeps its row.
class RetrieveFlowDefsAction extends Action {
  RetrieveFlowDefsAction(this.ids);

  final List<String> ids;

  /// The definition of the flow [id] is being read in [store]: one of
  /// these actions in progress has it among its [ids]. An action is in
  /// progress from the moment its dispatch returns until it has ended,
  /// also when it failed, so nothing is left behind.
  ///
  /// One action reads several ids, which a `statusKey` (one value per
  /// action) cannot say; the store's own set of actions in progress can.
  static bool reading(Store<AppState> store, String id) => store
      .actionsInProgress()
      .whereType<RetrieveFlowDefsAction>()
      .any((a) => a.ids.contains(id));

  /// The facts of [id]'s newest definition under [base] (`…/dataflows`),
  /// or null when there is none or it may not be read.
  static Future<FlowDefFacts?> read(WyrmApi api, String base, String id) async {
    try {
      final defs = await api.invoke('$base/$id', 'history').toList();
      final read = defs.isEmpty
          ? null
          : newestFlowOf(id, defs.first).orWarn('flow $id');
      if (read != null) {
        final d = read.draft;
        final k = flowKeysOf(d);
        return (
          reads: k.reads.lock,
          writes: k.writes.lock,
          blocks: d.blocks.length,
        );
      }
    } on WyrmException {
      // A flow whose history the user may not read lists without it.
    }
    return null;
  }

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || ids.isEmpty) {
      return null;
    }
    final base = '$root/dataflows';
    final got = await Future.wait([
      for (final id in ids) read(deps.wyrm, base, id),
    ]);
    if (site.root != root) {
      return null;
    }
    var table = flows.table;
    for (final (i, id) in ids.indexed) {
      final f = got[i];
      final row = table[id];
      if (row == null) {
        continue;
      }
      // The version read now, also when its definition could not be: it
      // is not asked for again until the version changes.
      final version =
          flowSummaryOfValue(id, live.values['$base/$id']?.value).version ??
          row.version;
      table = table.add(
        id,
        f == null
            ? row.copyWith(version: version)
            : row.copyWith(
                version: version,
                reads: f.reads,
                writes: f.writes,
                blocks: f.blocks,
              ),
      );
    }
    return table == flows.table ? null : state.copyWith.flows(table: table);
  }
}
