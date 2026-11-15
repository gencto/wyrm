import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/retrieve_links_action.dart';
import '../../live/actions/watch_keys_action.dart';
import 'retrieve_nodes_action.dart';

/// Explorer's tab is shown: its keys are watched (ADR 0037 rule 5: only keys
/// on screen are subscribed) and kept in `nodes.watching`; the tree and the
/// links are read when they never were.
class ShowExplorerAction extends Action {
  @override
  AppState? reduce() {
    final keys = ExplorerView(state).watchKeys;
    dispatchSync(WatchKeysAction(keys), notify: false);
    // started in parallel, each with its own wait
    dispatchAll([
      if (nodes.expanded.isEmpty) RetrieveNodesAction(),
      if (links.view.isEmpty) RetrieveLinksAction(),
    ]);
    return state.copyWith.nodes(watching: keys.lock);
  }
}
