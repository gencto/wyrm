import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../views/actions/add_view_keys_action.dart';
import '../../views/actions/set_view_children_action.dart';
import '../../views/actions/set_view_data_action.dart';
import 'view_bridge.dart';

/// The bridge's writes and findings as dispatches on the `views` slice.
class ViewBridgeDispatcher implements ViewBridgeServiceListener {
  ViewBridgeDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onData(Map<String, Object?> changed) =>
      _store.dispatchSync(SetViewDataAction(changed));

  @override
  void onKeys(Map<String, String> states) =>
      _store.dispatchSync(AddViewKeysAction(states));

  @override
  void onChildren(String key, List<String> names) =>
      _store.dispatchSync(SetViewChildrenAction(key, names));
}
