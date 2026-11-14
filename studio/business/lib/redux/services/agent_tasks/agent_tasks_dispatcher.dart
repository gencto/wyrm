import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/task_state.dart';

import '../../app_state.dart';
import '../../tasks/actions/add_tasks_action.dart';
import '../../tasks/actions/retrieve_task_record_action.dart';
import 'agent_tasks.dart';

/// Writes a task's state and the step of its run into the `tasks` table,
/// keeping what is known of the rest of its record.
class AgentTasksDispatcher implements AgentTasksServiceListener {
  AgentTasksDispatcher({required this._store});

  final Store<AppState> _store;

  /// The step a task's run is at, the latest one that ended, the number of
  /// suggestions, whether the model reviews the run and the task that
  /// replaced it, as last heard: when any moves, the record has something
  /// new (a review ends with the state still `failed`).
  final _seen = <String, (int, int, int, bool, String?)>{};

  @override
  void onTaskState(
    String id,
    TaskState state, {
    int step = 0,
    int finished = 0,
    int suggestions = 0,
    bool reviewing = false,
    String? replacedBy,
  }) {
    final known = _store.state.tasks.table[id];
    final now = (step, finished, suggestions, reviewing, replacedBy);
    final moved = _seen[id] != now;
    _seen[id] = now;
    if (known?.state == state && !moved) {
      return;
    }
    final task = (known ?? AgentTask(id: id)).copyWith(
      state: state,
      step: step,
      reviewing: reviewing,
      // a task replaced while another one is on screen says so in the list
      replacedBy: replacedBy ?? known?.replacedBy,
    );
    _store.dispatchSync(AddTasksAction([task].lock));
    // The record moved with the state and with each step: the task on
    // screen is read again.
    if (_store.state.tasks.selectedTask == id) {
      unawaited(_store.dispatchAndWait(RetrieveTaskRecordAction(id)));
    }
  }
}
