import 'package:models/assistant_panel.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// *New task* in the Assistant tab: no task is selected, and the panel on
/// the right is *This task* again; one state.
class NewTaskAction extends Action {
  @override
  AppState? reduce() {
    if (tasks.selectedTask == null && assistant.panel == AssistantPanel.task) {
      return null;
    }
    return state.copyWith
        .tasks(selectedTask: null)
        .copyWith
        .assistant(panel: AssistantPanel.task);
  }
}
