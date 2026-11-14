import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'load_assistant_action.dart';
import 'set_chip_action.dart';

/// Opens or closes the Assistant drawer over Explorer (⌘J, spec
/// `assistant.md` §5). Opening reads the agent and its tasks (the
/// Assistant tab may never have been shown) and puts the node selected in
/// Explorer as the first `@` chip of the next ask.
class SetDrawerAction extends Action {
  SetDrawerAction({required this.open});

  /// Opens it when it is closed, and the other way round.
  SetDrawerAction.toggle() : open = null;

  final bool? open;

  @override
  AppState? reduce() {
    final now = open ?? !assistant.drawer;
    if (now == assistant.drawer) {
      return null;
    }
    if (now) {
      if (nodes.selectedNode case final node?) {
        dispatchSync(SetChipAction(node));
      }
      unawaited(dispatchAndWait(LoadAssistantAction()));
    }
    return state.copyWith.assistant(drawer: now);
  }
}
