import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// `Use the password` on the lock card: the password checks the kept
/// session (`POST /api/confirm`, which also confirms it for the step-up),
/// so the session, the subscriptions and *Review and apply* stay. A wrong
/// password says so on the card.
class UnlockWithPasswordAction extends Action with NonReentrant, WaitingAction {
  UnlockWithPasswordAction(this.password);

  final String password;

  @override
  Future<AppState?> reduce() async {
    final session = deps.rawSession;
    if (session == null || !state.device.locked) {
      return null;
    }
    try {
      await session.confirmWithPassword(password);
    } on WyrmException catch (e) {
      return state.copyWith.device(lockError: e.code ?? e.message);
    }
    deps.idleLock.arm(Duration(minutes: state.device.lockAfter));
    return state.copyWith.device(locked: false, lockError: null);
  }
}
