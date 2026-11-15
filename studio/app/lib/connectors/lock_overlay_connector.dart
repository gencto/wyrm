import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/note_activity_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/device/actions/unlock_with_password_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/overlays/lock_screen.dart';

import '../mappers/device_mappers.dart';
import '../mappers/log_in_mappers.dart';
import '../navigation/leave_on_log_out_action.dart';

/// The idle lock over the Studio shell [child] (ADR 0050 §1.4, board
/// `UnlockLock`), and the clock's touch on the person's input. Typed
/// values to `LockScreen`, which words them; one action per intent.
class LockOverlayConnector extends StatelessWidget {
  const LockOverlayConnector({required this.child, this.onLogOut, super.key});

  final Widget child;

  /// The shell's own log out (it also leaves the page); the lock's own
  /// without one.
  final VoidCallback? onLogOut;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LockScreen(
      vm: vm.lock,
      onUnlock: vm.onUnlock,
      onPassword: vm.onPassword,
      onLogOut: onLogOut ?? vm.onLogOut,
      onActivity: vm.onActivity,
      child: child,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LockOverlayConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    lock: device.locked
        ? LockScreenVm(
            user: login.formUser,
            site: site.name ?? '',
            lockAfter: device.lockAfter,
            method: device.kind.method,
            kept: changes.view.length,
            problem: device.lockError?.problem,
            checking: device.isUnlocking,
            passwordOnly: !device.keyUsable,
          )
        : null,
    // A key the gateway refuses logs Studio out: the log-in page says why.
    onUnlock: device.keyUsable
        ? () => dispatch(LeaveOnLogOutAction(UnlockWithDeviceAction()))
        : null,
    onPassword: (p) => dispatch(UnlockWithPasswordAction(p)),
    onLogOut: () => dispatch(LeaveOnLogOutAction(LogOutAction())),
    onActivity: () => dispatchSync(NoteActivityAction()),
  );
}

/// What the lock draws ([lock], compared), whether the key can be tried
/// (compared), and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.lock,
    required this.onUnlock,
    required this.onPassword,
    required this.onLogOut,
    required this.onActivity,
  }) : super(equals: [lock, onUnlock != null]);

  final LockScreenVm? lock;
  final VoidCallback? onUnlock;
  final ValueChanged<String> onPassword;
  final VoidCallback onLogOut;
  final VoidCallback onActivity;
}
