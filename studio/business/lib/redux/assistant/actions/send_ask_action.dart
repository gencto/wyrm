import 'package:models/task_state.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../tasks/actions/answer_task_action.dart';
import 'ask_agent_action.dart';

/// The box is sent. While the task on screen waits for an answer, the box
/// answers it in the person's own words; else it is an ask that follows
/// the task on screen when the user may ([askParent], the same selector
/// that says beforehand that a plan that waits is replaced). In the drawer
/// ([drawer]) a question about the selection is a task of its own: it
/// never follows (nor replaces) the task on screen.
class SendAskAction extends Action {
  SendAskAction({this.drawer = false});

  final bool drawer;

  @override
  Future<AppState?> reduce() async {
    final t = shownTask;
    if (t != null && t.state == TaskState.awaitingAnswer) {
      await dispatchAndWait(AnswerTaskAction(t.id, text: assistant.draft));
    } else {
      await dispatchAndWait(
        AskAgentAction(parent: drawer ? null : askParent(t)),
      );
    }
    return null;
  }
}
