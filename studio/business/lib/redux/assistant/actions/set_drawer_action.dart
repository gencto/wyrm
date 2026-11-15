import '../../../wyrm/context_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_chip_action.dart';

/// Opens or closes the Assistant drawer over Explorer (⌘J, spec
/// `assistant.md` §5). Opening puts the node selected in Explorer as the
/// first `@` chip of the next ask, when the agent reads it (unknown before
/// the agent's meta is read: then it is put); the drawer, once shown,
/// reads the agent and its tasks (`ShowDrawerAction`).
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
      // a key the agent does not read would refuse the whole ask
      final root = site.root;
      if (nodes.selectedNode case final node?
          when root != null &&
              contextKey(root, node) == node &&
              (!assistant.readsKnown ||
                  agentReads(
                    root,
                    assistant.agent,
                    assistant.prefixes,
                    node,
                  ))) {
        dispatchSync(SetChipAction(node), notify: false);
      }
    }
    return state.copyWith.assistant(drawer: now);
  }
}
