import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Lists the agent's tasks (`<agent>/tasks` children): their ids; their
/// states arrive live through `AgentTasksService`.
class RetrieveTasksAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null) {
      return null;
    }
    List<Child> ids;
    try {
      ids = await deps.wyrm.children('$agent/tasks');
    } on WyrmException {
      ids = const [];
    }
    // another site was viewed meanwhile: these are its agent's tasks
    if (assistant.agent != agent) {
      return null;
    }
    final table = state.tasks.table;
    final tasks = [
      for (final c in ids) table[c.name] ?? AgentTask(id: c.name),
    ];
    return state.copyWith.tasks(
      table: table.addAll(
        IMap<String, AgentTask>.fromValues(
          values: tasks,
          keyMapper: (t) => t.id,
        ),
      ),
      view: [for (final t in tasks.reversed) t.id].lock,
    );
  }
}
