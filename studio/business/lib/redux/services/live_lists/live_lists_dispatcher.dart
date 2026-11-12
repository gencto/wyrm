import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../flows/actions/apply_flows_list_action.dart';
import '../../historian/actions/apply_history_list_action.dart';
import 'live_lists.dart';

/// Hands each list update to the screen whose key it is: `dataflows` to
/// Flows, `sys/history` and its groups to History. Each action checks the
/// key against the site on screen, so a late update of the site left
/// behind changes nothing.
class LiveListsDispatcher implements LiveListsServiceListener {
  LiveListsDispatcher({required this._store});

  final Store<AppState> _store;

  void _route(String parent, ListChange change) {
    if (parent.endsWith('/dataflows')) {
      _store.dispatchSync(ApplyFlowsListAction(parent, change));
    } else if (parent.contains('/sys/history')) {
      _store.dispatchSync(ApplyHistoryListAction(parent, change));
    }
  }

  @override
  void onChildren(String parent, List<Child> children) =>
      _route(parent, ListChange.all(children));

  @override
  void onChild(String parent, Child child) =>
      _route(parent, ListChange.one(child));

  @override
  void onRemoved(String parent, String name) =>
      _route(parent, ListChange.gone(name));
}

/// One update of a live list, as the screens' actions take it: the whole
/// list ([ListChange.all]), one child added or changed ([ListChange.one]),
/// or one gone ([ListChange.gone]).
final class ListChange {
  const ListChange.all(List<Child> this.children) : child = null, name = null;
  const ListChange.one(Child this.child) : children = null, name = null;
  const ListChange.gone(String this.name) : children = null, child = null;

  final List<Child>? children;
  final Child? child;
  final String? name;
}
