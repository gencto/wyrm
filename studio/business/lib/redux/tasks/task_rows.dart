import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/task_event.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../wyrm/mappers/agent_task_mapper.dart';
import '../../wyrm/mappers/values.dart';
import '../common/action.dart';
import 'actions/add_task_event_action.dart';
import 'actions/add_tasks_action.dart';

/// One row of the stream of `ask` or `answer` (`{task, state}`, then
/// `{task, event, text}` with `text`, `tool`, `question`, `state`, `wait`)
/// as an event of the task's conversation and, for a state, the task's
/// state.
mixin TaskRows on Action {
  void takeTaskRow(String task, Value r) {
    final event = str(r['event']);
    final text = str(r['text']) ?? str(r['state']) ?? '';
    void setState(String? s) {
      final known = state.tasks.table[task];
      if (known != null) {
        dispatchSync(
          AddTasksAction([known.copyWith(state: taskStateOf(s))].lock),
        );
      }
    }

    switch (event) {
      case 'wait':
        break;
      case null when r['state'] != null:
        setState(str(r['state']));
      case 'state':
        setState(text);
        dispatchSync(
          AddTaskEventAction(
            task,
            TaskEvent(kind: 'state', text: text, time: DateTime.now()),
          ),
        );
      case _:
        dispatchSync(
          AddTaskEventAction(
            task,
            TaskEvent(kind: event ?? 'text', text: text, time: DateTime.now()),
          ),
        );
    }
  }
}
