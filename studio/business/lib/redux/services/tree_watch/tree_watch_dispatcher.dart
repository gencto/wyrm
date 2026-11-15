import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/error_kind.dart';
import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../nodes/actions/child_added_action.dart';
import '../../nodes/actions/children_listed_action.dart';
import '../../nodes/actions/remove_nodes_action.dart';
import '../../nodes/actions/retry_read_action.dart';
import '../../nodes/actions/set_children_action.dart';
import '../../nodes/actions/set_list_failed_action.dart';
import '../../problems/actions/add_problem_action.dart';
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
  void onListError(String parent, Object error) {
    // The branch shows no children. A node the user may not list is simply
    // empty for them; any other failure is the `read failed` mark on its
    // row and a quiet problem (docs/design/specs/errors.md §4).
    _store.dispatchSync(SetChildrenAction(parent, const IListConst([])));
    if (error case final WyrmException w
        when w.status.known != Status.permissionDenied) {
      final e = refusalOf(w, key: parent, call: 'list');
      _store
        ..dispatchSync(SetListFailedAction(parent, w.status.name))
        ..dispatchSync(
          AddProblemAction(
            e.copyWith(
              quiet: true,
              stream: e.kind == ErrorKind.reach ? e.site : null,
              retry: () => RetryReadAction(parent),
            ),
          ),
        );
    }
  }
}
