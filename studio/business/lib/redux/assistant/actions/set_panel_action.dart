import 'package:models/assistant_panel.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_agent_secrets_action.dart';

/// Shows [panel] on the right of the Assistant. *What it may do* then
/// reads the names of the agent's secrets: the panel is shown at once, the
/// names follow when they arrive.
class SetPanelAction extends Action {
  SetPanelAction(this.panel);

  final AssistantPanel panel;

  @override
  Future<AppState?> reduce() async {
    if (panel != assistant.panel) {
      dispatchSync(_Panel(panel));
    }
    if (panel == AssistantPanel.rights) {
      await dispatchAndWait(RetrieveAgentSecretsAction());
    }
    return null;
  }
}

class _Panel extends Action {
  _Panel(this.panel);

  final AssistantPanel panel;

  @override
  AppState reduce() => state.copyWith.assistant(panel: panel);
}
