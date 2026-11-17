import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../live/actions/follow_list_action.dart';
import '../../live/actions/live_list_failed_action.dart';
import 'live_lists.dart';

/// Hands each list update to the screen whose key it is, one action each
/// (`FollowListAction`: `dataflows` to Flows, `sys/history` and its groups
/// to History; `LiveListFailedAction` for a failed list). A stream
/// listener does not wait (studio-rules §1): it dispatches and returns.
class LiveListsDispatcher implements LiveListsServiceListener {
  LiveListsDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onChildren(String parent, List<Child> children) =>
      _store.dispatch(FollowListAction(parent, ListChange.all(children)));

  @override
  void onChild(String parent, Child child) =>
      _store.dispatch(FollowListAction(parent, ListChange.one(child)));

  @override
  void onRemoved(String parent, String name) =>
      _store.dispatch(FollowListAction(parent, ListChange.gone(name)));

  @override
  void onListError(String parent, Object error) =>
      _store.dispatch(LiveListFailedAction(parent, error));
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
