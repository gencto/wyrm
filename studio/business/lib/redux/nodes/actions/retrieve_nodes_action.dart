import '../../app_state.dart';
import '../../common/action.dart';
import 'toggle_node_action.dart';

/// Opens the tree of the site on screen: its `downstream` section is listed
/// at once (the other sections open on a tap).
///
/// [preload] names more sections (`dataflows`, `storage`) whose live lists
/// open now without opening them in the tree, so their children are in
/// `nodes.table` before the user taps them (the log-in preload,
/// docs/design/specs/login.md §5). A tap then finds the list already open.
class RetrieveNodesAction extends Action with WaitingAction {
  RetrieveNodesAction({this.preload = const [], super.quiet});

  final List<String> preload;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root != null) {
      dispatch(ToggleNodeAction('$root/downstream', open: true));
      for (final s in preload) {
        deps.treeWatch.open('$root/$s');
      }
    }
    return null;
  }
}
