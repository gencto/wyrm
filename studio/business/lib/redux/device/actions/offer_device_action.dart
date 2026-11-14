import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';

import '../../../wyrm/device_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../models/device_state.dart';

/// What comes after a password login and before Welcome (ADR 0050,
/// unlock-discover.md §2):
///
/// 1. A key that stopped working here (`stale`) has its gateway record
///    removed now (`DELETE /api/devices/<id>`; a failure is ignored, the
///    record cannot log in anyway).
/// 2. After `changed` or `signedOut` with `Turn <name> on again` ticked, the
///    new key is made at once (`EnableDeviceAction` via [enable]) and no
///    offer is shown; `password_due` needs no new key.
/// 3. Else the offer (`device.stage` = `offer`) once per gateway, user and
///    computer: devices on at the gateway, a strong biometric here, Remember
///    on, no key yet, never `Don't ask on this computer`.
/// 4. With no biometric here, the offer's own form says so once per
///    computer (board `UnlockOffer` on Linux) unless the log-in page did.
///
/// Returns with `device.stage` = `offer` when the page must wait for the
/// person, else `none`.
class OfferDeviceAction extends Action {
  OfferDeviceAction({required this.enable});

  /// Makes and registers a key (the connector passes `EnableDeviceAction`
  /// with its prompt's words).
  final Future<void> Function() enable;

  @override
  Future<AppState?> reduce() async {
    final account = accountOf(login.gateway, login.user);
    final session = deps.session;
    if (account == null || session == null) {
      return state.copyWith.device(stage: UnlockStage.none);
    }
    final records = deps.deviceRecords;
    var record = await records.read(account.origin, account.user);
    if (record.stale) {
      if (record.deviceId case final id?) {
        try {
          await session.removeDevice(id);
        } on Object {
          // Gone already, or the gateway refuses: it cannot log in anyway.
        }
      }
      record = record.copyWith(
        deviceId: () => null,
        alias: () => null,
        stale: false,
      );
      await records.write(account.origin, account.user, record);
    }
    final d = state.device;
    var policy = d.policy;
    if (policy == null) {
      final info = await deps.login.info(account.gateway);
      if (info != null) {
        policy = policyOf(info.devices);
      }
    }
    final on = policy?.enabled ?? false;
    final back =
        (d.stage == UnlockStage.changed || d.stage == UnlockStage.signedOut) &&
        d.reEnable &&
        d.refusal != UnlockRefusal.devicesOff &&
        d.refusal != UnlockRefusal.passwordDue;
    final base = d.copyWith(
      policy: policy,
      keyId: record.alias,
      deviceId: record.deviceId,
      stale: false,
      refusal: null,
      reason: null,
    );
    if (back && on && d.available && !record.usable) {
      dispatchSync(_Device(base.copyWith(stage: UnlockStage.none)));
      await enable();
      return null;
    }
    if (on &&
        d.available &&
        !record.usable &&
        !record.dontAsk &&
        !record.offered &&
        login.remember) {
      await records.write(
        account.origin,
        account.user,
        record.copyWith(offered: true),
      );
      return state.copyWith(
        device: base.copyWith(stage: UnlockStage.offer, offered: true),
      );
    }
    if (on && !d.available && !d.noticed && login.remember) {
      await records.markNoticed();
      return state.copyWith(
        device: base.copyWith(stage: UnlockStage.offer, noticed: true),
      );
    }
    return state.copyWith(device: base.copyWith(stage: UnlockStage.none));
  }
}

class _Device extends Action {
  _Device(this.next);

  final DeviceState next;

  @override
  AppState reduce() => state.copyWith(device: next);
}
