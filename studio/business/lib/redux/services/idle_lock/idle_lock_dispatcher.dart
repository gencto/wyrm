import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../device/actions/lock_action.dart';
import 'idle_lock.dart';

class IdleLockDispatcher implements IdleLockServiceListener {
  IdleLockDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onIdle() => _store.dispatchSync(LockAction());
}
