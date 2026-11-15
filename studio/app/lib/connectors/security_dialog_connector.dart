import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/remove_device_action.dart';
import 'package:business/redux/device/actions/retrieve_devices_action.dart';
import 'package:business/redux/device/actions/set_device_unlock_action.dart';
import 'package:business/redux/device/actions/set_lock_after_action.dart';
import 'package:business/redux/device/actions/sign_out_everywhere_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/device_policy_info.dart';
import 'package:ui/overlays/security_dialog.dart';

import '../mappers/device_mappers.dart';
import '../mappers/security_mappers.dart';
import '../navigation/leave_on_log_out_action.dart';

/// Account › Security (ADR 0050 §1.5, board `UnlockApp`), opened from the
/// avatar menu (`showSecurityDialog`): this computer's unlock and lock
/// delay, the devices of the user on the site, `Sign out everywhere`.
///
/// The reference connector of studio-rules: it reads selectors, maps the
/// domain's enums through `app/lib/mappers/`, passes typed values (no
/// `S.current`: the dialog words them) and starts one action per intent.
class SecurityDialogConnector extends StatelessWidget {
  const SecurityDialogConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) => store.dispatch(RetrieveDevicesAction(quiet: true)),
    builder: (context, vm) => SecurityDialog(
      vm: vm.dialog,
      onUnlock: vm.onUnlock,
      onLockAfter: vm.onLockAfter,
      onDevice: vm.onDevice,
      onSignOut: () {
        Navigator.of(context).pop();
        vm.onSignOut();
      },
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SecurityDialogConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _vm(
    now: DateTime.now(),
    policy: device.policy ?? const DevicePolicyInfo(),
  );

  // An arrow body, not a block: `tool/check_rules.dart` reads a block that
  // holds several callbacks as one callback with several dispatches.
  _Vm _vm({required DateTime now, required DevicePolicyInfo policy}) => _Vm(
    dialog: SecurityDialogVm(
      user: (login.user ?? '').trim(),
      site: site.name ?? '',
      os: hostPlatform().os,
      method: device.kind.method,
      devices: [
        for (final x in device.devices)
          x.securityRow(thisDeviceId: device.deviceId, now: now),
      ],
      biometricHere: device.available,
      unlockOn: device.unlockOn,
      unlockEnabled: device.unlockAllowed,
      keyAdded: momentOf(device.added),
      lockAfter: device.lockAfter,
      lockMax: device.lockMaxMin,
      confirmOn: device.confirmsConfig,
      policyOn: policy.enabled,
      maxPerUser: policy.maxPerUser,
      passwordEveryDays: policy.passwordEveryDays,
      busy: device.isSettingUnlock,
      askPassword: device.needPassword,
      passwordWrong: device.passwordRefused,
      passwordError: device.securityError,
    ),
    onUnlock: (r) => dispatch(
      SetDeviceUnlockAction(on: r.on, reason: r.reason, password: r.password),
    ),
    onLockAfter: (m) => dispatch(SetLockAfterAction(m)),
    onDevice: (id) => dispatch(RemoveDeviceAction(id)),
    onSignOut: () => dispatch(LeaveOnLogOutAction(SignOutEverywhereAction())),
  );
}

/// What the dialog draws ([dialog], compared) and what it starts (not).
class _Vm extends Vm {
  _Vm({
    required this.dialog,
    required this.onUnlock,
    required this.onLockAfter,
    required this.onDevice,
    required this.onSignOut,
  }) : super(equals: [dialog]);

  final SecurityDialogVm dialog;
  final ValueChanged<UnlockRequest> onUnlock;
  final ValueChanged<int> onLockAfter;
  final ValueChanged<String> onDevice;
  final VoidCallback onSignOut;
}
