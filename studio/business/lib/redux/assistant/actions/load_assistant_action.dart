import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../tasks/actions/retrieve_task_record_action.dart';
import '../../tasks/actions/retrieve_tasks_action.dart';
import 'retrieve_agent_action.dart';

/// Reads what the Assistant shows for the site on screen: the links (when
/// none are known yet) to find the agent link, the agent, its tasks, and
/// the record of the selected task. Dispatched when the tab is shown, and
/// again by `deps.reloads` while it is shown (the socket is back, another
/// site is viewed).
class LoadAssistantAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (links.table.isEmpty) {
      await dispatchAndWait(RetrieveLinksAction());
    }
    await dispatchAndWait(RetrieveAgentAction());
    await dispatchAndWait(RetrieveTasksAction());
    if (tasks.selectedTask case final id?) {
      await dispatchAndWait(RetrieveTaskRecordAction(id));
    }
    return null;
  }
}
