import 'package:async_redux/async_redux.dart' show ActionStatus;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/task_event.dart';
import 'package:models/task_event_kind.dart';
import 'package:models/task_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../wyrm/decode/agent_task.dart';
import '../common/action.dart';
import 'actions/add_task_event_action.dart';
import 'actions/add_tasks_action.dart';
import 'actions/retrieve_task_record_action.dart';

/// One row of the stream of `ask` or `answer` ([AgentReply]: `{task,
/// state}`, then `{task, event, text}` with `text`, `tool`, `question`,
/// `state`, `wait`) as an event of the task's conversation and, for a
/// state, the task's state.
///
/// A state row starts a read of the task's record, with its own wait; the
/// action that takes the rows awaits those reads ([rowReads]) before it
/// ends, so it owns every read it started.
mixin TaskRows on Action {
  final _reads = <Future<ActionStatus>>[];

  /// The reads of the record the rows started, done.
  Future<void> rowReads() => Future.wait(_reads);

  void takeTaskRow(String task, AgentReply r) {
    switch (r) {
      case AgentReplyState(:final state):
        _setState(task, taskStateOf(state));
      case AgentReplyEvent(kind: AgentEventKind.wait):
        break;
      case AgentReplyEvent(kind: AgentEventKind.state, :final text):
        final reached = AgentTaskState.fromWire(text);
        if (reached != null) {
          _setState(task, taskStateOf(reached), notify: false);
        }
        // The stream may be ahead of the task's `~val` (the gateway
        // forwards the two on their own): the tasks service then sees no
        // change of state and reads nothing. The record that goes with
        // this state (its questions, its plan) is read here, with its own
        // wait.
        _reads.add(dispatchAndWait(RetrieveTaskRecordAction(task)));
        dispatchSync(
          AddTaskEventAction(
            task,
            TaskEvent(
              kind: reached == null ? TaskEventKind.note : TaskEventKind.state,
              text: text,
              state: reached == null ? null : taskStateOf(reached),
              time: DateTime.now(),
            ),
          ),
        );
      case AgentReplyEvent(:final kind, :final text):
        dispatchSync(
          AddTaskEventAction(
            task,
            TaskEvent(
              kind: switch (kind) {
                AgentEventKind.text => TaskEventKind.text,
                AgentEventKind.tool => TaskEventKind.tool,
                AgentEventKind.question => TaskEventKind.question,
                // handled above
                AgentEventKind.state ||
                AgentEventKind.wait => TaskEventKind.note,
              },
              text: text,
              time: DateTime.now(),
            ),
          ),
        );
    }
  }

  /// The task's state, as the stream says it; a state row and its event
  /// are one change on screen, so the state alone does not notify.
  void _setState(String task, TaskState s, {bool notify = true}) {
    final known = state.tasks.table[task];
    if (known != null && known.state != s) {
      dispatchSync(
        AddTasksAction([known.copyWith(state: s)].lock),
        notify: notify,
      );
    }
  }
}
