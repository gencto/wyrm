import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/task_state.dart';

import '../../app_state.dart';
import '../../tasks/actions/add_tasks_action.dart';
import '../../tasks/actions/retrieve_task_record_action.dart';
import 'agent_tasks.dart';

/// Writes a task's state into the `tasks` table, keeping what is known of
/// the rest of its record.
class AgentTasksDispatcher implements AgentTasksServiceListener {
  AgentTasksDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onTaskState(String id, TaskState state) {
    final known = _store.state.tasks.table[id];
    if (known?.state == state) {
      return;
    }
    final task = (known ?? AgentTask(id: id)).copyWith(state: state);
    _store.dispatchSync(AddTasksAction([task].lock));
    // The record moved with the state: the task on screen is read again.
    if (_store.state.tasks.selectedTask == id) {
      unawaited(_store.dispatchAndWait(RetrieveTaskRecordAction(id)));
    }
  }
}
