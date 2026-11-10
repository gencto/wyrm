import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/agent_task.dart';
import 'package:models/error_kind.dart';
import 'package:models/task_event.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../tasks/actions/add_task_event_action.dart';
import '../../tasks/actions/add_tasks_action.dart';

/// `<agent>` ▸ `ask {task}` (write): a stream of `{task, state}` then
/// `{task, event, text}` rows (`text` from the model, `tool` it used to
/// read, `state` it reached). Each row becomes an event of the task, so
/// the conversation fills as the agent works.
class AskAgentAction extends Action with NonReentrant, WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final ask = (assistant.draft ?? '').trim();
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
      await for (final r in deps.wyrm.invoke(
        agent,
        'ask',
        Value.from({'task': ask}),
      )) {
        final task = str(r['task']);
        if (task == null) {
          continue;
        }
        if (id == null) {
          id = task;
          dispatchSync(
            AddTasksAction(
              [AgentTask(id: task, ask: ask, owner: site.user ?? '')].lock,
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
          dispatchSync(_ClearDraft());
        }
        final event = str(r['event']);
        final text = str(r['text']) ?? str(r['state']) ?? '';
        switch (event) {
          case 'wait':
            break;
          case null when r['state'] != null:
            _state(task, str(r['state']));
          case 'state':
            _state(task, text);
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
                TaskEvent(
                  kind: event ?? 'text',
                  text: text,
                  time: DateTime.now(),
                ),
              ),
            );
        }
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

  void _state(String id, String? s) {
    final known = state.tasks.table[id];
    if (known != null) {
      dispatchSync(
        AddTasksAction([known.copyWith(state: taskStateOf(s))].lock),
      );
    }
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
