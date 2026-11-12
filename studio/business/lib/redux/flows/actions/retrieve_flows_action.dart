import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/flow_summary.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_flow_defs_action.dart';

/// Reads the flows of the site: `dataflows` children, each flow's `~val`
/// (`{state, error, version, deployed_by}`) and its newest definition
/// (`dataflows/<id>` ▸ `history`) for what it reads and writes.
class RetrieveFlowsAction extends Action with WaitingAction {
  RetrieveFlowsAction({super.quiet});

  @override
  Action again() => RetrieveFlowsAction(quiet: quiet);

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/dataflows';
    final ids = await listOf(api, base);
    final vals = await readValues(api, '$base/*');
    final flows = <FlowSummary>[];
    for (final c in ids) {
      final v = vals['$base/${c.name}'];
      final def = await RetrieveFlowDefsAction.read(api, base, c.name);
      final state = integer(v?['state']);
      flows.add(
        FlowSummary(
          id: c.name,
          version: integer(v?['version']),
          deployedBy: str(v?['deployed_by']),
          problem: state == 2 ? (str(v?['error']) ?? 'error') : null,
          draft: state == null,
          reads: def?.reads ?? const IListConst([]),
          writes: def?.writes ?? const IListConst([]),
          blocks: def?.blocks ?? 0,
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
