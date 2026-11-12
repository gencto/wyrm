import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

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
/// Not in `Wait` as an action (a live change is not a refresh of the
/// screen, so no sweep bar): each id is a [reading] flag instead, which
/// `ApplyFlowValuesAction` asks so a version that arrives during the read
/// does not read it twice. A flow whose history the user may not read
/// keeps its row.
class RetrieveFlowDefsAction extends Action {
  RetrieveFlowDefsAction(this.ids);

  final List<String> ids;

  /// The `Wait` flag of a definition being read; the flow id is its ref.
  static const reading = 'flowDefReading';

  @override
  Future<void> before() async {
    // Before the first await: the flags are up as the dispatch returns.
    for (final id in ids) {
      dispatchSync(WaitAction.add(reading, ref: id), notify: false);
    }
    await super.before();
  }

  @override
  void after() {
    super.after();
    for (final id in ids) {
      dispatchSync(WaitAction.remove(reading, ref: id), notify: false);
    }
  }

  /// The facts of [id]'s newest definition under [base] (`…/dataflows`),
  /// or null when there is none or it may not be read.
  static Future<FlowDefFacts?> read(WyrmApi api, String base, String id) async {
    try {
      final defs = await api.invoke('$base/$id', 'history').toList();
      final list = defs.isEmpty ? null : defs.first;
      if (list case VArray(:final v) when v.isNotEmpty) {
        final d = flowDraftOf(id, v.last);
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
