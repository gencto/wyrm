import 'package:device_key/device_key.dart';
import 'package:models/error_kind.dart';
import 'package:models/unlock_stage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Use <name>` (board `UnlockOffer`), `Turn <name> on again after I log in`,
/// and the switch in Account › Security: makes a key in the OS store
/// and registers it (`POST /api/devices`; the new key signs the register
/// nonce, which on Apple platforms and Android is the first prompt, with
/// [reason]). The record keeps the device id and the key's alias.
///
/// The gateway needs a password check in the last 5 minutes: after a
/// password login it has one. From Account › Security it may not:
/// `password_required` sets `device.needPassword`, and the dialog asks for
/// the password ([password], checked by `POST /api/confirm` first).
///
/// Any other failure deletes the key, leaves the form and fails quietly:
/// a toast `<name> could not be turned on: <reason>` (spec §2).
class EnableDeviceAction extends Action with WaitingAction {
  EnableDeviceAction({required this.reason, this.password})
    : super(quiet: true);

  final String reason;

  /// The password of a fresh check before the registration.
  final String? password;

  @override
  Future<AppState?> reduce() async {
    final account = accountOf(login.gateway, login.user);
    final session = deps.session;
    final site = this.site.name ?? device.keySite;
    if (account == null || session == null || site == null) {
      return null;
    }
    final keys = deps.deviceKey;
    final alias = keyAlias(account.origin, account.user);
    final name = device.name ?? 'biometrics';
    try {
      if (password case final pw?) {
        await session.confirmWithPassword(pw);
      }
      final pub = await keys.create(
        alias,
        allowDeviceCredential: device.policy?.allowDeviceCredential ?? false,
      );
      final String id;
      try {
        id = await session.registerDevice(
          site: site,
          user: account.user,
          name: deviceName(),
          platform: devicePlatform(),
          alg: pub.alg,
          publicKey: pub.publicKey,
          sign: signer(keys, alias, reason),
        );
      } on Object {
        await keys.delete(alias);
        rethrow;
      }
      final now = nowS();
      final records = deps.deviceRecords;
      final r = await records.read(account.origin, account.user);
      await records.write(
        account.origin,
        account.user,
        r.copyWith(
          site: site,
          deviceId: () => id,
          alias: () => alias,
          added: now,
          lastUsed: now,
          stale: false,
          offered: true,
        ),
      );
      return state.copyWith.device(
        keyId: alias,
        deviceId: id,
        keySite: site,
        added: now,
        lastUsed: now,
        stale: false,
        offered: true,
        stage: UnlockStage.none,
        needPassword: false,
        securityError: null,
      );
    } on WyrmException catch (e) {
      if (e.code == 'password_required') {
        dispatchSync(_NeedPassword());
        return null;
      }
      if (e.code == 'bad_password') {
        dispatchSync(_NeedPassword(error: e.code));
        return null;
      }
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.reach,
        e.message,
        call: 'enable_device',
        thing: name,
      );
    } on DeviceKeyException catch (e) {
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.studio,
        e.message.isEmpty ? e.code.name : e.message,
        call: 'enable_device',
        thing: name,
      );
    } on SignStopped catch (e) {
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.studio,
        '$e',
        call: 'enable_device',
        thing: name,
      );
    }
  }
}

/// The form goes on to Welcome whatever happened.
class _Left extends Action {
  @override
  AppState reduce() => state.copyWith.device(stage: UnlockStage.none);
}

/// Account › Security asks for the password before the key.
class _NeedPassword extends Action {
  _NeedPassword({this.error});

  final String? error;

  @override
  AppState reduce() =>
      state.copyWith.device(needPassword: true, securityError: error);
}
