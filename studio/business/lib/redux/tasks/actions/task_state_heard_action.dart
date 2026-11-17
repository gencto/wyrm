import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/task_state.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'add_tasks_action.dart';
import 'retrieve_task_record_action.dart';

/// The agent's `~val` of task [id] was heard: its [heard] and the step of
/// its run go into the `tasks` table, keeping what is known of the rest of
/// its record; when the task is the one on screen its record is read
/// again, the last step (`RetrieveTaskRecordAction`: its own wait, in turn
/// with the other reads of the task). [moved]: a field of the run changed
/// since the last one heard (the listener remembers them). It changes no
/// state itself beyond the table.
class TaskStateHeardAction extends Action {
  TaskStateHeardAction(
    this.id,
    this.heard, {
    required this.moved,
    this.step = 0,
    this.reviewing = false,
    this.replacedBy,
  });

  final String id;
  final TaskState heard;
  final bool moved;
  final int step;
  final bool reviewing;
  final String? replacedBy;

  @override
  Future<AppState?> reduce() async {
    final known = tasks.table[id];
    if (known?.state == heard && !moved) {
      return null;
    }
    final task = (known ?? AgentTask(id: id)).copyWith(
      state: heard,
      step: step,
      reviewing: reviewing,
      // a task replaced while another one is on screen says so in the list
      replacedBy: replacedBy ?? known?.replacedBy,
    );
    dispatchSync(AddTasksAction([task].lock));
    // The record moved with the state and with each step: the task on
    // screen is read again.
    if (tasks.selectedTask == id) {
      await dispatchAndWait(RetrieveTaskRecordAction(id));
    }
    return null;
  }
}
