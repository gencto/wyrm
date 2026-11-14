import '../../../wyrm/device_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Lock Studio after` in Account › Security: off (0), 5, 15 or 30 minutes,
/// never more than the gateway's `idle_lock_max_min`. Kept per gateway and
/// user on this computer; the clock starts again with it.
class SetLockAfterAction extends Action {
  SetLockAfterAction(this.minutes);

  final int minutes;

  @override
  Future<AppState?> reduce() async {
    final max = state.device.policy?.idleLockMaxMin;
    final m = max != null && max > 0 && minutes > max ? max : minutes;
    final account = accountOf(login.gateway, login.user);
    if (account != null) {
      final records = deps.deviceRecords;
      final r = await records.read(account.origin, account.user);
      await records.write(
        account.origin,
        account.user,
        r.copyWith(lockAfter: m),
      );
    }
    if (deps.session != null) {
      deps.idleLock.arm(Duration(minutes: m));
    }
    return state.copyWith.device(lockAfter: m < 0 ? 0 : m);
  }
}
