import '../../app_state.dart';
import '../../common/action.dart';
import 'toggle_node_action.dart';

/// Opens the tree of the site on screen: its `downstream` section is listed
/// at once (the other sections open on a tap).
class RetrieveNodesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root != null) {
      dispatch(ToggleNodeAction('$root/downstream', open: true));
    }
    return null;
  }
}
