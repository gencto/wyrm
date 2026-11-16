import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_details_action.dart';
import '../../nodes/actions/toggle_node_action.dart';

/// A node of the palette's Tree tab opens or closes (spec §18): shown at
/// once. A node's actions are in its own `~meta`: read once, when it is
/// first opened here (the tree's lists do not carry them), the last step
/// of the toggle. It changes no state itself (`null`).
class ToggleTreeNodeAction extends Action {
  ToggleTreeNodeAction(this.key);

  final String key;

  @override
  Future<AppState?> reduce() async {
    final opening = !nodes.expanded.contains(key);
    dispatchSync(ToggleNodeAction(key));
    if (opening && !nodes.detail.containsKey(key)) {
      await dispatchAndWait(RetrieveDetailsAction([key]));
    }
    return null;
  }
}
