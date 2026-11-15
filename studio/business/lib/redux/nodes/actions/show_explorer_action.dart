import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import 'retrieve_nodes_action.dart';
import 'watch_explorer_action.dart';

/// Explorer's tab is shown: its keys are watched at once
/// ([WatchExplorerAction]); the tree and the links are read when they
/// never were, in parallel, and this action ends when they have answered.
class ShowExplorerAction extends Action {
  @override
  Future<AppState?> reduce() async {
    dispatchSync(WatchExplorerAction());
    await Future.wait([
      if (nodes.expanded.isEmpty) dispatchAndWait(RetrieveNodesAction()),
      if (links.view.isEmpty) dispatchAndWait(RetrieveLinksAction()),
    ]);
    return null;
  }
}
