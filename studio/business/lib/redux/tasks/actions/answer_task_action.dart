import 'package:async_redux/async_redux.dart';
import 'package:models/agent_task.dart';
import 'package:models/task_event.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../task_rows.dart';
import 'add_task_event_action.dart';
import 'retrieve_task_record_action.dart';

/// `<agent>/tasks/<id>` ▸ `answer {answers?, text?}` (ADR 0049 §5): the
/// options picked on the choices card, by question id, or [text], the
/// person's own words for the whole card. A stream like `ask`: the model
/// goes on, and its lines fill the conversation.
///
/// Only questions that still wait are answered; one without a pick is left
/// to the agent link (it gets [text], or no answer).
class AnswerTaskAction extends Action
    with TaskRows, NonReentrant, WaitingAction {
  AnswerTaskAction(this.id, {this.text});

  final String id;
  final String? text;

  @override
  Future<AppState?> reduce() async {
    final agent = assistant.agent;
    final task = tasks.table[id];
    if (agent == null || task == null || task.state != .awaitingAnswer) {
      return null;
    }
    final words = text?.trim();
    final answers = <String, Object>{
      if (words == null || words.isEmpty)
        for (final q in task.questions)
          if (!q.answered)
            if (assistant.picks['$id/${q.id}'] case final picked?)
              // in the card's order, not the order of the taps
              q.id: [
                for (final o in q.options)
                  if (picked.contains(o.id)) o.id,
              ],
    };
    if (answers.isEmpty && (words == null || words.isEmpty)) {
      return null;
    }
    final key = '$agent/tasks/$id';
    final said = words != null && words.isNotEmpty
        ? words
        : [
            for (final q in task.questions)
              if (answers[q.id] case final List<String> ids)
                for (final o in q.options)
                  if (ids.contains(o.id)) o.label,
          ].join(', ');
    try {
      await for (final r in deps.wyrm.answerTask(
        key,
        answers: answers,
        text: words != null && words.isNotEmpty ? words : null,
      )) {
        if (str(r['task']) != null) {
          _said(task, said, words);
          takeTaskRow(id, r);
        }
      }
      _said(task, said, words);
    } on WyrmException catch (e) {
      // the task may have moved on (answered elsewhere, a restart): the
      // record says where it is
      await dispatchAndWait(RetrieveTaskRecordAction(id));
      throw StudioException.refused(
        e,
        key: key,
        call: 'answer',
        thing: id,
        write: true,
      );
    }
    await dispatchAndWait(RetrieveTaskRecordAction(id));
    final picks = assistant.picks.removeWhere((k, _) => k.startsWith('$id/'));
    return state.copyWith.assistant(
      picks: picks,
      // the words were sent: the box is free
      draft: words != null && words.isNotEmpty ? null : assistant.draft,
    );
  }

  var _told = false;

  /// The answer as a line of the conversation, once the call was taken
  /// (its first row, or its end): a refused answer leaves no line. A task
  /// opened from its record has no events of this session yet: its
  /// conversation so far ([conversationOf], the record before the answer)
  /// comes first, so it does not vanish when the session's events start.
  void _said(AgentTask task, String said, String? words) {
    if (_told) {
      return;
    }
    _told = true;
    if (tasks.events[id]?.isEmpty ?? true) {
      for (final e in conversationOf(task)) {
        dispatchSync(AddTaskEventAction(id, e));
      }
    }
    dispatchSync(
      AddTaskEventAction(
        id,
        TaskEvent(
          kind: words != null && words.isNotEmpty ? 'ask' : 'answer',
          text: said,
          time: DateTime.now(),
        ),
      ),
    );
  }
}
