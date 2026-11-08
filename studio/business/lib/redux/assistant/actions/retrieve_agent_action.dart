import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The settings of the agent link that say what it may do, in this order
/// (docs/studio.md §7.8). `api_key_ref` is the name of the secret; whether
/// the secret is set is not readable (§10 item 12).
const shownCfg = [
  'model',
  'require_approval',
  'allowed_prefixes',
  'budget_tokens_day',
  'api_key_ref',
];

/// Finds the agent link of the site on screen (a link of driver `agent`),
/// reads what it may do (its root `cfg`, the keys of [shownCfg]) and follows
/// its tasks' states.
class RetrieveAgentAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final id = links.table.values
        .where((l) => l.driver == 'agent')
        .map((l) => l.id)
        .firstOrNull;
    if (id == null) {
      deps.agentTasks.follow(null);
      return state.copyWith.assistant(agent: null, cfg: const IMapConst({}));
    }
    final key = '$root/downstream/$id';
    var cfg = const <String, String>{};
    try {
      final m = await deps.wyrm.meta(key);
      cfg = {
        for (final e in (m.cfg ?? const <String, Value>{}).entries)
          if (shownCfg.contains(e.key)) e.key: _shown(e.value),
      };
    } on WyrmException {
      // The agent's meta needs list rights on it.
    }
    deps.agentTasks.follow(key);
    return state.copyWith.assistant(agent: key, cfg: cfg.lock);
  }

  static String _shown(Value v) => switch (toDart(v)) {
    final List<Object?> l => l.isEmpty ? '-' : l.join(', '),
    null => '-',
    final Object o => '$o',
  };
}
