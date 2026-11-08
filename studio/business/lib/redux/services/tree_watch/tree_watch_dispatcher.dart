import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/node_info.dart';

import '../../app_state.dart';
import '../../nodes/actions/add_nodes_action.dart';
import '../../nodes/actions/remove_nodes_action.dart';
import '../../nodes/actions/set_children_action.dart';
import 'tree_watch.dart';

/// Turns list updates into the `nodes` table.
class TreeWatchDispatcher implements TreeWatchServiceListener {
  TreeWatchDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onChildren(String parent, List<NodeInfo> children) =>
      _store.dispatchSync(SetChildrenAction(parent, children.lock));

  @override
  void onChild(String parent, NodeInfo child) =>
      _store.dispatchSync(AddNodesAction([child].lock));

  @override
  void onRemoved(String parent, String name) =>
      _store.dispatchSync(RemoveNodesAction('$parent/$name'));

  @override
  void onListError(String parent, Object error) =>
      // The branch shows no children; the error is not the user's to act on
      // here (a node they may not list is simply empty for them).
      _store.dispatchSync(SetChildrenAction(parent, const IListConst([])));
}
