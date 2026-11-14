import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_tasks_action.dart';

/// Reads the record of task [id]: its `~state` document through the
/// gateway's `doc` (ADR 0049 §1): the ask, the owner, the plan with its
/// results, the log, the error. Dispatched when a task is selected and on
/// each change of its state.
///
/// A gateway older than `doc` answers `unknown op`: the assistant then
/// remembers that documents are not readable (`assistant.docs`) and shows
/// its note instead of the plan. A record the user may not read (somebody
/// else's task) leaves the task as it is.
class RetrieveTaskRecordAction extends Action with WaitingAction {
  RetrieveTaskRecordAction(this.id) : super(quiet: true);

  final String id;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    if (agent == null || !assistant.docs) {
      return null;
    }
    try {
      final record = await deps.wyrm.doc('$agent/tasks/$id', '~state');
      dispatchSync(AddTasksAction([agentTaskOf(id, record)].lock));
    } on WyrmException catch (e) {
      if (isUnknownOp(e)) {
        return state.copyWith.assistant(docs: false);
      }
      if (e.status.known != Status.permissionDenied &&
          e.status.known != Status.notFound) {
        rethrow;
      }
    }
    return null;
  }
}
