import 'package:device_key/device_key.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/error_subject.dart';
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
/// [reason], else `deps.prompts.enable` of the site and the user). The
/// record keeps the device id and the key's alias.
///
/// The gateway needs a password check in the last 5 minutes: after a
/// password login it has one. From Account › Security it may not:
/// `password_required` sets `device.needPassword`, and the dialog asks for
/// the password ([password], checked by `POST /api/confirm` first).
///
/// Any other failure deletes the key, leaves the form and fails quietly:
/// a toast `<name> could not be turned on: <reason>` (spec §2).
class EnableDeviceAction extends Action with WaitingAction {
  EnableDeviceAction({this.reason, this.password}) : super(quiet: true);

  /// The prompt's line; null for the words of `deps.prompts`.
  final String? reason;

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
    // What is turned on: the method as the system names it, else
    // *biometrics* (the app's word).
    final name = device.name;
    final subject = name == null ? ErrorSubject.biometrics : null;
    // The gateway takes a device key only from a platform of its set: on
    // linux and the web Studio refuses here, and sends nothing.
    final host = hostPlatform();
    final platform = host.device;
    if (platform == null) {
      dispatchSync(_Left());
      throw StudioException.hinted(
        ErrorKind.studio,
        ErrorHint.noDeviceKey(host),
        call: const .known(.enableDevice),
        thing: name,
        subject: subject,
      );
    }
    try {
      if (password case final pw?) {
        await session.confirmWithPassword(pw);
      }
      final pub = await keys.create(
        alias,
        allowDeviceCredential: device.policy?.allowDeviceCredential ?? false,
      );
      final alg = DeviceAlg.fromWire(pub.alg);
      if (alg == null) {
        await keys.delete(alias);
        throw DeviceKeyException(
          DeviceKeyErrorCode.failed,
          'a key of an unknown algorithm: ${pub.alg}',
        );
      }
      final prompt = reason ?? deps.prompts.enable(site, account.user);
      final String id;
      try {
        id = await session.addDevice(
          site: site,
          user: account.user,
          name: deviceName(),
          platform: platform,
          alg: alg,
          publicKey: pub.publicKey,
          sign: signer(keys, alias, prompt),
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
          role: this.site.role,
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
        passwordRefused: false,
      );
    } on WyrmException catch (e) {
      final refusal = e.refusal;
      if (refusal == GatewayRefusal.passwordRequired ||
          refusal == GatewayRefusal.badPassword) {
        dispatchSync(
          _NeedPassword(refused: refusal == GatewayRefusal.badPassword),
        );
        return null;
      }
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.reach,
        e.message,
        call: const .known(.enableDevice),
        thing: name,
        subject: subject,
      );
    } on DeviceKeyException catch (e) {
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.studio,
        e.message.isEmpty ? e.code.name : e.message,
        call: const .known(.enableDevice),
        thing: name,
        subject: subject,
      );
    } on SignStopped catch (e) {
      dispatchSync(_Left());
      throw StudioException.said(
        ErrorKind.studio,
        '$e',
        call: const .known(.enableDevice),
        thing: name,
        subject: subject,
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
  _NeedPassword({this.refused = false});

  /// The password given was wrong.
  final bool refused;

  @override
  AppState reduce() =>
      state.copyWith.device(needPassword: true, passwordRefused: refused);
}
