import '../../../wyrm/mappers/agent_task_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'ask_agent_action.dart';

/// The person picked the suggestion [suggestion] of the task [task] (a fix
/// on a step, a way out of a stopped run, *Make a plan for n units*): a
/// follow-up `ask {parent: task, task: <text>, context: <row keys>}` (ADR
/// 0049 amendment). The text is what the card showed (`label. detail`,
/// the labels of the ticked rows), taken from the record in the store,
/// never from the widget; the context is the keys of the ticked rows. A
/// suggestion with rows and none ticked sends nothing.
///
/// A task that waits for approval or an answer is replaced by the new one
/// (its plan can no longer be approved); the card of a fix says so before
/// the pick. The new task is selected.
class PickSuggestionAction extends Action {
  PickSuggestionAction(this.task, this.suggestion);

  final String task;
  final String suggestion;

  @override
  Future<AppState?> reduce() async {
    final s = tasks.table[task]?.suggestions
        .where((s) => s.id == suggestion)
        .firstOrNull;
    if (s == null) {
      return null;
    }
    final ticked = assistant.rowPicks['$task/$suggestion'];
    final rows = [
      for (final r in s.rows)
        if (ticked?.contains(r.key) ?? false) r,
    ];
    if (s.rows.isNotEmpty && rows.isEmpty) {
      return null;
    }
    final status = await dispatchAndWait(
      AskAgentAction(
        text: suggestionAsk(s, rows),
        parent: task,
        context: [for (final r in rows) r.key],
      ),
    );
    if (!status.isCompletedOk) {
      return null;
    }
    return state.copyWith.assistant(
      rowPicks: assistant.rowPicks.remove('$task/$suggestion'),
    );
  }
}
