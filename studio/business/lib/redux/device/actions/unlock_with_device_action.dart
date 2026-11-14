import 'package:async_redux/async_redux.dart';
import 'package:device_key/device_key.dart';
import 'package:models/error_kind.dart';
import 'package:models/login_failure.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../../wyrm/failures.dart';
import '../../../wyrm/session.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../login/actions/log_in_action.dart';
import '../../login/actions/probe_gateway_action.dart';
import '../../login/actions/set_login_progress_action.dart';
import '../../session/actions/log_out_action.dart';
import 'load_device_action.dart';

/// Unlocks with the device key (ADR 0050 §1.2, §1.4; unlock-discover.md §2):
/// on the log-in page a device login, inside a locked Studio an idle unlock
/// that keeps the session.
///
/// 1. The gateway is probed first: one that does not answer is the log-in
///    page's unreachable state, and the key is not tried.
/// 2. A challenge, the OS prompt with [reason], then the gateway checks the
///    signature (`device.stage` is `checking` from the prompt on).
/// 3. What comes back picks the form (spec §2, *When it does not work*):
///    - cancelled, missed, locked out, no biometric now → `fallback`, the
///      key kept;
///    - the key no longer opens → `changed`: the key is deleted, the
///      gateway's record after the password login;
///    - `device_removed`, `password_changed`, `devices_off` and a bare
///      refusal → `signedOut`, the key deleted; `password_due` →
///      `signedOut`, the key kept (the password login clears it).
///
/// [auto] is the one prompt the page opens by itself when its window gets
/// the focus: it runs once per start, never again after a cancel.
class UnlockWithDeviceAction extends Action with NonReentrant, WaitingAction {
  UnlockWithDeviceAction({required this.reason, this.auto = false});

  /// The prompt's line: `sign in to plant as olena`.
  final String reason;

  /// The page's own prompt on focus, not a press.
  final bool auto;

  /// A prompt left open longer than this lets the challenge run out: its
  /// bare refusal then says nothing about the key.
  static const _slow = Duration(seconds: 50);

  @override
  Future<AppState?> reduce() async {
    if (auto && device.autoPrompted) {
      return null;
    }
    final d = state.device;
    final alias = d.keyId;
    final id = d.deviceId;
    final site = d.keySite;
    final account = accountOf(login.gateway, login.user);
    if (alias == null || id == null || site == null || account == null) {
      return state.copyWith.device(autoPrompted: true);
    }
    dispatchSync(_Stage(UnlockStage.unlock, autoPrompted: true));
    final locked = d.locked && deps.session != null;
    final watch = Stopwatch()..start();
    final sign = signer(
      deps.deviceKey,
      alias,
      reason,
      onSigned: () => dispatchSync(_Stage(UnlockStage.checking)),
    );
    try {
      if (locked) {
        await deps.rawSession!.unlock(
          site: site,
          user: account.user,
          device: id,
          sign: sign,
        );
        await _used(account.origin, account.user);
        deps.idleLock.arm(Duration(minutes: d.lockAfter));
        return state.copyWith.device(
          locked: false,
          lockError: null,
          stage: UnlockStage.none,
        );
      }
      final gateway = await _reachable(account.gateway);
      final session = await deps.login.openWithDevice(
        gateway,
        site: site,
        user: account.user,
        device: id,
        sign: sign,
      );
      final opened = await openedSession(this, session, account.user, gateway);
      await _used(account.origin, account.user, role: opened.site.role);
      return opened.copyWith(
        login: opened.login.copyWith(
          password: null,
          failure: null,
          reason: null,
          recent: remembered(opened.login.recent, login.gateway!),
          preload: 0,
        ),
        device: opened.device.copyWith(
          stage: UnlockStage.none,
          refusal: null,
          reason: null,
          lastUsed: nowS(),
        ),
      );
    } on SignStopped catch (e) {
      return _stopped(e.result, account.origin, account.user, locked);
    } on WyrmException catch (e) {
      final slow = watch.elapsed > _slow;
      final refusal = unlockRefusalOf(e);
      if (refusal == null || (refusal == UnlockRefusal.unknown && slow)) {
        // Not a word about the key (a limit, a prompt that outlived its
        // challenge): the password, the key kept.
        return state.copyWith.device(
          stage: locked ? UnlockStage.none : UnlockStage.fallback,
          lockError: locked ? e.message : null,
          reason: e.message,
        );
      }
      return _refused(refusal, account.origin, account.user, locked);
    } on _Unreachable {
      return state.copyWith.device(stage: UnlockStage.unlock);
    } on UserException {
      rethrow;
    } on Object catch (e) {
      // No answer after the probe: the log-in page's unreachable state.
      dispatchSync(
        SetLoginProgressAction(
          failure: LoginFailure.unreachable,
          reason: faultLine(e),
        ),
      );
      throw StudioException.said(
        ErrorKind.reach,
        faultLine(e),
        call: 'log_in',
        thing: '${account.gateway}',
      ).withDialog(false);
    }
  }

  /// The first gateway of the field that answers a probe; none → the
  /// unreachable state, without a prompt.
  Future<Uri> _reachable(Uri first) async {
    final gateways = parseGateways(login.gateway ?? '');
    final probes = <String, int>{};
    GatewayProbe? last;
    for (final g in gateways.isEmpty ? [first] : gateways) {
      last = await deps.login.probe(g);
      probes[gatewayKey(g)] = last.ms ?? -1;
      if (last.answered) {
        dispatchSync(SetLoginProgressAction(probes: probes));
        return g;
      }
    }
    dispatchSync(
      SetLoginProgressAction(
        failure: LoginFailure.unreachable,
        reason: last?.reason,
        probes: probes,
      ),
    );
    throw const _Unreachable();
  }

  Future<void> _used(String origin, String user, {String? role}) async {
    final r = await deps.deviceRecords.read(origin, user);
    await deps.deviceRecords.write(
      origin,
      user,
      r.copyWith(lastUsed: nowS(), role: role),
    );
  }

  Future<AppState> _stopped(
    SignResult r,
    String origin,
    String user,
    bool locked,
  ) async {
    if (r is SignInvalidated) {
      await _dropKey(origin, user);
      if (locked) {
        // The lock card asks for the password now.
        return state.copyWith.device(keyId: null, stale: true);
      }
      return state.copyWith.device(
        keyId: null,
        stale: true,
        stage: UnlockStage.changed,
        reEnable: true,
      );
    }
    // Cancelled, missed, locked out, unavailable, failed: the key stays.
    final why = SignStopped(r).toString();
    if (locked) {
      return state.copyWith.device(stage: UnlockStage.none, lockError: null);
    }
    return state.copyWith.device(stage: UnlockStage.fallback, reason: why);
  }

  Future<AppState?> _refused(
    UnlockRefusal refusal,
    String origin,
    String user,
    bool locked,
  ) async {
    if (refusal != UnlockRefusal.passwordDue) {
      await _dropKey(origin, user);
    }
    final next = state.copyWith.device(
      keyId: refusal == UnlockRefusal.passwordDue ? state.device.keyId : null,
      stale: refusal != UnlockRefusal.passwordDue,
      stage: UnlockStage.signedOut,
      refusal: refusal,
      reEnable: refusal != UnlockRefusal.devicesOff,
    );
    if (locked) {
      // The kept session is no good with this key: Studio logs out, and the
      // log-in page says why.
      await deps.detach();
      return loggedOut(next);
    }
    return next;
  }

  /// Deletes the key; the record keeps its device id, marked stale, so the
  /// gateway's record is removed after the next password login.
  Future<void> _dropKey(String origin, String user) async {
    final r = await recordOf(this);
    if (r.alias case final alias?) {
      await deps.deviceKey.delete(alias);
    }
    await deps.deviceRecords.write(
      origin,
      user,
      r.copyWith(alias: () => null, stale: true),
    );
  }
}

/// The form while the unlock runs.
class _Stage extends Action {
  _Stage(this.stage, {this.autoPrompted});

  final UnlockStage stage;
  final bool? autoPrompted;

  @override
  AppState reduce() => state.copyWith.device(
    stage: stage,
    autoPrompted: autoPrompted ?? state.device.autoPrompted,
  );
}

final class _Unreachable implements Exception {
  const _Unreachable();
}
