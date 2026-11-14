import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/error_kind.dart';
import 'package:models/task_event.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../tasks/actions/add_task_event_action.dart';
import '../../tasks/actions/add_tasks_action.dart';
import '../../tasks/task_rows.dart';

/// `<agent>` ▸ `ask {task}` (write): a stream of `{task, state}` then
/// `{task, event, text}` rows (`text` from the model, `tool` it used to
/// read, `state` it reached). Each row becomes an event of the task, so
/// the conversation fills as the agent works.
///
/// With [text] the ask is that text and the draft in the box stays; with
/// [parent] it follows that task (`ask {task, parent}`, ADR 0049 §9): the
/// model gets the parent's ask, plan and results.
class AskAgentAction extends Action with TaskRows, NonReentrant, WaitingAction {
  AskAgentAction({this.text, this.parent});

  final String? text;
  final String? parent;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final ask = (text ?? assistant.draft ?? '').trim();
    if (agent == null) {
      throw StudioException.said(
        ErrorKind.gone,
        'There is no assistant link on this site.',
        call: 'ask',
        thing: 'assistant',
      );
    }
    if (ask.isEmpty) {
      return null;
    }
    String? id;
    try {
      await for (final r in deps.wyrm.askAgent(agent, ask, parent: parent)) {
        final task = str(r['task']);
        if (task == null) {
          continue;
        }
        if (id == null) {
          id = task;
          dispatchSync(
            AddTasksAction(
              [
                AgentTask(
                  id: task,
                  ask: ask,
                  owner: site.user ?? '',
                  parent: parent,
                ),
              ].lock,
            ),
          );
          dispatchSync(
            AddTaskEventAction(
              task,
              TaskEvent(kind: 'ask', text: ask, time: DateTime.now()),
            ),
          );
          dispatchSync(_Select(task));
          // The ask is taken: the box is free for the next one.
          if (text == null) {
            dispatchSync(_ClearDraft());
          }
        }
        takeTaskRow(task, r);
      }
    } on WyrmException catch (e) {
      if (id != null) {
        dispatchSync(
          AddTaskEventAction(
            id,
            TaskEvent(kind: 'error', text: e.message, time: DateTime.now()),
          ),
        );
      }
      throw StudioException.refused(
        e,
        key: agent,
        call: 'ask',
        thing: 'assistant',
        write: true,
      );
    }
    if (id == null) {
      // The stream ended without naming a task: nothing was started, and
      // the ask stays in the box (an agent without its API key does this).
      throw StudioException.said(
        ErrorKind.broker,
        'The assistant started no task. Check that its API key is set.',
        key: agent,
        call: 'ask',
        thing: 'assistant',
      );
    }
    return null;
  }
}

class _ClearDraft extends Action {
  @override
  AppState reduce() => state.copyWith.assistant(draft: null);
}

class _Select extends Action {
  _Select(this.id);

  final String id;

  @override
  AppState reduce() => state.copyWith.tasks(selectedTask: id);
}
