import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_node_detail_action.dart';
import 'select_node_action.dart';
import 'set_menu_asked_action.dart';

/// The node menu of [key] (tree `⋯`, right click, Actions ▾): the node is
/// selected and the menu opens once its `~meta` is read (its actions are
/// the menu). While it waits, `waiting.nodeMenu` says so; the menu asked
/// last is the one that opens: an answer for a menu asked before (another
/// node's, or the same one asked again) or for a node no longer on screen
/// is dropped. A failed read opens no menu (the node shows `read failed`).
class OpenNodeMenuAction extends Action with WaitingAction {
  OpenNodeMenuAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetMenuAskedAction(key), notify: false);
    if (key != nodes.selectedNode) {
      await dispatchAndWait(SelectNodeAction(key));
    } else if (!nodes.detail.containsKey(key)) {
      await dispatchAndWait(RetrieveNodeDetailAction(key, quiet: true));
    }
    if (nodes.menuAsked != key ||
        nodes.selectedNode != key ||
        !nodes.detail.containsKey(key)) {
      return null;
    }
    return state.copyWith.nodes(menu: key, menuAsked: null);
  }
}
