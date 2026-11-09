import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/flow_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads the flows of the site: `dataflows` children, each flow's `~val`
/// (`{state, error, version, deployed_by}`) and its newest definition
/// (`dataflows/<id>` ▸ `history`) for what it reads and writes.
class RetrieveFlowsAction extends Action with WaitingAction {
  RetrieveFlowsAction({super.quiet});

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/dataflows';
    final ids = await call('Cannot list the flows', () => api.children(base));
    final vals = await readValues(api, '$base/*');
    final flows = <FlowSummary>[];
    for (final c in ids) {
      final v = vals['$base/${c.name}'];
      var reads = const <String>[];
      var writes = const <String>[];
      var count = 0;
      try {
        final defs = await api.invoke('$base/${c.name}', 'history').toList();
        final list = defs.isEmpty ? null : defs.first;
        if (list case VArray(:final v) when v.isNotEmpty) {
          final d = flowDraftOf(c.name, v.last);
          final k = flowKeysOf(d);
          reads = k.reads;
          writes = k.writes;
          count = d.blocks.length;
        }
      } on WyrmException {
        // A flow whose history the user may not read lists without it.
      }
      final state = integer(v?['state']);
      flows.add(
        FlowSummary(
          id: c.name,
          version: integer(v?['version']),
          deployedBy: str(v?['deployed_by']),
          problem: state == 2 ? (str(v?['error']) ?? 'error') : null,
          draft: state == null,
          reads: reads.lock,
          writes: writes.lock,
          blocks: count,
          description: c.meta.displayName,
          running: state == 0,
        ),
      );
    }
    return state.copyWith.flows(
      table: IMap<String, FlowSummary>.fromValues(
        values: flows,
        keyMapper: (f) => f.id,
      ),
      view: [for (final f in flows) f.id].lock,
    );
  }
}
