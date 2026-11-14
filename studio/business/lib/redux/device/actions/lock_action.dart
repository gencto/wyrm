import '../../app_state.dart';
import '../../common/action.dart';

/// The idle lock (ADR 0050 §1.4, board `UnlockLock`): the shell hides the
/// tree and the values under a card. The session, the subscriptions and
/// *Review and apply* stay. Only with a session and a lock delay set.
class LockAction extends Action {
  @override
  AppState? reduce() {
    if (deps.session == null || state.device.locked) {
      return null;
    }
    deps.idleLock.stop();
    return state.copyWith.device(locked: true, lockError: null);
  }
}
