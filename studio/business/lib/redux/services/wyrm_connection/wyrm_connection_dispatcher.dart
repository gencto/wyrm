import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../site/actions/set_connected_action.dart';
import 'wyrm_connection.dart';

/// Writes `site.connected`; when the socket is back after a loss, every
/// screen's read runs again through [onReconnect].
class WyrmConnectionDispatcher implements WyrmConnectionServiceListener {
  WyrmConnectionDispatcher({required this._store, this.onReconnect});

  final Store<AppState> _store;

  /// The reads to run again after a reconnect (set by `AppDependencies`).
  void Function(Store<AppState> store)? onReconnect;

  @override
  void onConnection({required bool connected}) {
    final was = SelectSite(_store.state).connected;
    if (was == connected) {
      return;
    }
    _store.dispatchSync(SetConnectedAction(connected));
    if (connected && SelectSession(_store.state).isAvailable) {
      onReconnect?.call(_store);
    }
  }
}
