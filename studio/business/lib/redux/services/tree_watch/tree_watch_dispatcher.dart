import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';

import '../../app_state.dart';
import '../../nodes/actions/child_added_action.dart';
import '../../nodes/actions/children_listed_action.dart';
import '../../nodes/actions/list_failed_action.dart';
import '../../nodes/actions/remove_nodes_action.dart';
import 'tree_watch.dart';

/// Turns list updates into the `nodes` table.
class TreeWatchDispatcher implements TreeWatchServiceListener {
  TreeWatchDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onChildren(String parent, List<NodeInfo> children) =>
      _store.dispatch(ChildrenListedAction(parent, children.lock));

  @override
  void onChild(String parent, NodeInfo child) =>
      _store.dispatch(ChildAddedAction(parent, child));

  @override
  void onRemoved(String parent, String name) =>
      _store.dispatchSync(RemoveNodesAction('$parent/$name'));

  @override
  void onListError(String parent, Object error) =>
      _store.dispatchSync(ListFailedAction(parent, error));
}
