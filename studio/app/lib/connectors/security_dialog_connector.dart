import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/remove_device_action.dart';
import 'package:business/redux/device/actions/retrieve_devices_action.dart';
import 'package:business/redux/device/actions/set_device_unlock_action.dart';
import 'package:business/redux/device/actions/set_lock_after_action.dart';
import 'package:business/redux/device/actions/sign_out_everywhere_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/user_device.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/security_dialog.dart';

import '../common/unlock.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

/// Account › Security (ADR 0050 §1.5, board `UnlockApp`), opened from the
/// avatar menu: this computer's unlock and lock delay, the devices of the
/// user on the site, `Sign out everywhere`.
class SecurityDialogConnector extends StatelessWidget {
  const SecurityDialogConnector({super.key});

  /// Opens the dialog over [context].
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierColor: const Color.fromRGBO(8, 10, 11, 0.6),
    builder: (_) => const Center(child: SecurityDialogConnector()),
  );

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) =>
        unawaited(store.dispatchAndWait(RetrieveDevicesAction(quiet: true))),
    builder: (context, vm) => SecurityDialog(
      vm: vm.dialog,
      onUnlock: vm.onUnlock,
      onPassword: vm.onPassword,
      onLockAfter: vm.onLockAfter,
      onDevice: vm.onDevice,
      onSignOut: () async {
        Navigator.of(context).pop();
        await vm.onSignOut();
      },
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

/// `mac`, `iOS`, `win`, `and` on the device tile.
String _os(String platform) => switch (platform) {
  'mac' => 'mac',
  'ios' => 'iOS',
  'windows' => 'win',
  'android' => 'and',
  final p => p.isEmpty ? '?' : p.substring(0, p.length < 3 ? p.length : 3),
};

/// The method a device record unlocks with, by its platform.
String _method(String platform) => switch (platform) {
  'mac' => 'Touch ID',
  'ios' => 'Face ID',
  'windows' => 'Windows Hello',
  'android' => S.current.unlockNameFingerprint,
  _ => S.current.unlockNameBiometric,
};

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SecurityDialogConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final d = state.device;
    final s = S.current;
    final platform = devicePlatform();
    final siteName = site.name ?? '';
    final user = (login.user ?? '').trim();
    final name = unlockName(d.kind);
    final policy = d.policy;
    final max = policy?.idleLockMaxMin ?? 30;
    final on = d.deviceId != null && d.keyId != null && !d.stale;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    SecurityDeviceVm row(UserDevice x) {
      final own = x.thisDevice || x.id == d.deviceId;
      final removed = x.state == 'removed';
      final dueDays = x.passwordDueAt == 0
          ? null
          : ((x.passwordDueAt - now) / 86400).ceil();
      final (tag, tone) = removed
          ? (
              s.securityRemovedBy(
                (x.removedBy ?? '').replaceFirst('user:', ''),
              ),
              Tone.bad,
            )
          : own
          ? (s.securityThisDevice, Tone.good)
          : x.state == 'signed_out'
          ? (s.securitySignedOut, Tone.neutral)
          : dueDays != null && dueDays <= 7
          ? (s.securityDue(dueDays < 0 ? 0 : dueDays), Tone.warn)
          : (null, Tone.neutral);
      final when = own && x.lastUsed > 0 && now - x.lastUsed < 60
          ? s.securityUsedNow
          : agoOf(x.lastUsed);
      return SecurityDeviceVm(
        id: x.id,
        os: _os(x.platform),
        name: x.name,
        tag: tag,
        tagTone: tone,
        detail: removed
            ? [_method(x.platform), s.securityRemoved].join(' · ')
            : [
                _method(x.platform),
                if (when.isNotEmpty) when,
                if (x.added > 0) s.securityAdded(shortDate(x.added)),
              ].join(' · '),
        action: own
            ? s.securityTurnOff
            : removed
            ? s.securityForget
            : s.securityRemove,
        own: own,
      );
    }

    final confirm = policy?.stepUp == 'config';
    return _Vm(
      dialog: SecurityDialogVm(
        title: s.securityTitle,
        subtitle: '$user · $siteName',
        onThis: s.securityOn(unlockDevice(platform)),
        unlockTitle: s.unlockWith(name),
        unlockText: !d.available
            ? s.securityNoBio
            : on
            ? s.securityUnlockDesc(
                unlockStore(platform),
                shortDate(d.added),
                unlockDevice(platform),
              )
            : s.securityUnlockOffDesc(unlockStore(platform)),
        unlockOn: on,
        unlockEnabled: d.available && (policy?.enabled ?? true),
        lockTitle: s.securityLockAfter,
        lockText: s.securityLockDesc(siteName, max),
        lockAfter: d.lockAfter,
        lockChoices: [
          (0, s.securityLockOff),
          for (final m in const [5, 15, 30])
            if (m <= max) (m, s.securityMinutes(m)),
        ],
        confirmTitle: s.securityConfirm,
        confirmText: confirm
            ? s.securityConfirmForced(siteName)
            : s.securityConfirmNone(siteName),
        confirmOn: confirm,
        devicesTitle: s.securityDevicesOn(siteName),
        devices: [for (final x in d.devices) row(x)],
        empty: s.securityNoDevices,
        policy: s.securityPolicy(
          siteName,
          (policy?.enabled ?? false) ? s.securityPolicyOn : s.securityPolicyOff,
          policy?.maxPerUser ?? 5,
          policy?.passwordEveryDays ?? 30,
          confirm ? s.securityPolicyConfirm : '',
        ),
        signOut: s.securitySignOutAll,
        busy: state.wait.isWaitingForType<SetDeviceUnlockAction>(),
        passwordLabel: d.needPassword
            ? s.securityPasswordNeeded(siteName)
            : null,
        passwordError: d.securityError == 'bad_password'
            ? s.lockWrongPassword
            : d.securityError,
        turnOn: s.securityTurnOn,
      ),
      onUnlock: (v) => unawaited(
        dispatchAndWait(
          SetDeviceUnlockAction(
            on: v,
            reason: s.unlockEnablePrompt(siteName, user),
          ),
        ),
      ),
      onPassword: (p) => unawaited(
        dispatchAndWait(
          SetDeviceUnlockAction(
            on: true,
            reason: s.unlockEnablePrompt(siteName, user),
            password: p,
          ),
        ),
      ),
      onLockAfter: (m) => unawaited(dispatchAndWait(SetLockAfterAction(m))),
      onDevice: (id) => unawaited(dispatchAndWait(RemoveDeviceAction(id))),
      onSignOut: () async {
        await dispatchAndWait(SignOutEverywhereAction());
        if (state.session.token == null) {
          dispatchSync(GoAction.replace(const LogInRoute()));
        }
      },
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.dialog,
    required this.onUnlock,
    required this.onPassword,
    required this.onLockAfter,
    required this.onDevice,
    required this.onSignOut,
  }) : super(equals: [dialog]);

  final SecurityDialogVm dialog;
  final ValueChanged<bool> onUnlock;
  final ValueChanged<String> onPassword;
  final ValueChanged<int> onLockAfter;
  final ValueChanged<String> onDevice;
  final Future<void> Function() onSignOut;
}
