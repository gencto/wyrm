import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'enable_device_action.dart';
import 'remove_device_action.dart';

/// The `Unlock with <name>` switch in Account › Security: on makes and
/// registers a key ([EnableDeviceAction]; a password check first when the
/// gateway asks for one), off removes this computer's device record and
/// its key.
class SetDeviceUnlockAction extends Action with NonReentrant, WaitingAction {
  SetDeviceUnlockAction({
    required this.on,
    required this.reason,
    this.password,
  });

  final bool on;
  final String reason;
  final String? password;

  @override
  Future<AppState?> reduce() async {
    if (on) {
      await dispatchAndWait(
        EnableDeviceAction(reason: reason, password: password),
      );
      return null;
    }
    final id = state.device.deviceId;
    if (id != null) {
      await dispatchAndWait(RemoveDeviceAction(id));
      return null;
    }
    return forgetOwnKey(this);
  }
}
