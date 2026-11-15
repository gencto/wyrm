import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/decode/agent_config.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Finds the agent link of the site on screen (a link of driver `agent`),
/// reads what it may do (its root `cfg`, decoded by [agentConfigOf]) and
/// follows its tasks' states.
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
      return state.copyWith.assistant(
        agent: null,
        config: null,
        secrets: null,
      );
    }
    final key = '$root/downstream/$id';
    final config = switch (await _meta(key)) {
      // a cfg Studio cannot read is logged with its field: what the agent
      // may do is then not known, as without the rights to read it
      final NodeMeta m => agentConfigOf(m.cfg ?? const {}).orWarn(key),
      null => null,
    };
    deps.agentTasks.follow(key);
    return state.copyWith.assistant(
      agent: key,
      config: config,
      // the names were of the agent read before (maybe another site's):
      // not known until they are read for this one
      secrets: key == assistant.agent ? assistant.secrets : null,
    );
  }

  /// The agent's meta; null when it cannot be read (it needs list rights).
  Future<NodeMeta?> _meta(String key) async {
    try {
      return await deps.wyrm.meta(key);
    } on WyrmException {
      return null;
    }
  }
}
