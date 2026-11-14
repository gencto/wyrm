import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:storage/storage.dart';

import '../../../wyrm/device_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads what the log-in page needs for the device unlock
/// (unlock-discover.md §2): whether this computer offers a biometric key,
/// the record of the gateway and user in the form, and the gateway's policy
/// from `/api/info`. Then it picks the form:
///
/// - a key that can sign → `unlock` (`Welcome back`);
/// - a key, but the gateway says devices are off → `signedOut` with
///   `devicesOff`, and the key is deleted (ADR 0050 §1.6);
/// - no biometric here, a remembered user, devices on, and not said before
///   on this computer → `noBiometrics`, said once (board `UnlockLinux`);
/// - else the password form.
///
/// A form a failed unlock chose in this run (fallback, changed, signed out)
/// stays: a new read does not hide why the key did not work. Runs when the
/// page opens and when the gateway or the user changes.
class LoadDeviceAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final keys = deps.deviceKey;
    final available = await keys.isAvailable();
    final records = deps.deviceRecords;
    final noticed = await records.noticed();
    final account = accountOf(login.gateway, login.user);
    var d = state.device.copyWith(
      available: available.available,
      kind: keyKindOf(available.kind),
      name: available.available ? available.name : null,
      noticed: noticed,
    );
    if (account == null) {
      return state.copyWith(device: d.copyWith(stage: UnlockStage.none));
    }
    final record = await records.read(account.origin, account.user);
    final info = await deps.login.info(account.gateway);
    final policy = info == null ? d.policy : policyOf(info.devices);
    d = d.copyWith(
      keyId: record.alias,
      deviceId: record.deviceId,
      added: record.added,
      lastUsed: record.lastUsed,
      keySite: info?.site ?? (record.site.isEmpty ? null : record.site),
      stale: record.stale,
      lockAfter: record.lockAfter,
      dontAsk: record.dontAsk,
      offered: record.offered,
      policy: policy,
    );
    const kept = {
      UnlockStage.fallback,
      UnlockStage.changed,
      UnlockStage.signedOut,
      UnlockStage.offer,
    };
    if (kept.contains(d.stage)) {
      return state.copyWith(device: d);
    }
    if (record.usable && policy != null && !policy.enabled) {
      // The gateway allows no device unlock now: Studio removes its key
      // (ADR 0050 §1.6) and says why; the gateway's record goes after the
      // password login.
      await keys.delete(record.alias!);
      await records.write(
        account.origin,
        account.user,
        record.copyWith(alias: () => null, stale: true),
      );
      return state.copyWith(
        device: d.copyWith(
          keyId: null,
          stale: true,
          stage: UnlockStage.signedOut,
          refusal: UnlockRefusal.devicesOff,
        ),
      );
    }
    if (record.usable && available.available) {
      return state.copyWith(device: d.copyWith(stage: UnlockStage.unlock));
    }
    if (!available.available &&
        !noticed &&
        (policy?.enabled ?? false) &&
        login.remember) {
      await records.markNoticed();
      return state.copyWith(
        device: d.copyWith(stage: UnlockStage.noBiometrics, noticed: true),
      );
    }
    return state.copyWith(device: d.copyWith(stage: UnlockStage.none));
  }
}

/// The record of the form's gateway and user (empty without one).
Future<DeviceRecord> recordOf(Action a) async {
  final account = accountOf(a.login.gateway, a.login.user);
  if (account == null) {
    return const DeviceRecord();
  }
  return a.deps.deviceRecords.read(account.origin, account.user);
}
