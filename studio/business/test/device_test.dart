import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/add_changes_action.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/device/actions/cancel_step_up_action.dart';
import 'package:business/redux/device/actions/confirm_step_up_action.dart';
import 'package:business/redux/device/actions/decline_offer_action.dart';
import 'package:business/redux/device/actions/enable_device_action.dart';
import 'package:business/redux/device/actions/load_device_action.dart';
import 'package:business/redux/device/actions/lock_action.dart';
import 'package:business/redux/device/actions/offer_device_action.dart';
import 'package:business/redux/device/actions/remove_device_action.dart';
import 'package:business/redux/device/actions/retrieve_devices_action.dart';
import 'package:business/redux/device/actions/retrieve_user_devices_action.dart';
import 'package:business/redux/device/actions/set_device_unlock_action.dart';
import 'package:business/redux/device/actions/set_lock_after_action.dart';
import 'package:business/redux/device/actions/sign_out_everywhere_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/device/actions/unlock_with_password_action.dart';
import 'package:business/redux/device/actions/use_password_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/services/idle_lock/idle_lock.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:business/wyrm/session.dart';
import 'package:device_key/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/login_failure.dart';
import 'package:models/staged_change.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _gateway = 'http://127.0.0.1:8445';
const _origin = 'http://127.0.0.1:8445';
const _user = 'admin';
const _reason = 'sign in to central as admin';

/// One computer: its settings, its key store and a gateway that checks
/// every signature (ADR 0050, unlock-discover.md §2, §3).
final class _Computer {
  _Computer({FakeDeviceKey? keys, FakeLogin? login})
    : keys = keys ?? FakeDeviceKey(),
      login = login ?? FakeLogin();

  final settings = InMemoryKeyValueStorage();
  final FakeDeviceKey keys;
  final FakeLogin login;

  FakeDevices get gateway => login.session.gateway;
  DeviceRecords get records => DeviceRecords(settings);

  Store<AppState> store() =>
      fakeStore(login: login, keys: keys, settings: settings);

  Future<Store<AppState>> loggedIn() async {
    final s = store();
    await fill(s);
    await s.dispatchAndWait(LoadDeviceAction());
    final status = await s.dispatchAndWait(LogInAction());
    expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
    return s;
  }

  /// A computer whose user turned the unlock on: a registered key.
  Future<void> enrolled() async {
    final s = await loggedIn();
    await s.dispatchAndWait(
      OfferDeviceAction(enable: () => _enable(s)),
    );
    expect(s.state.device.stage, UnlockStage.offer);
    await _enable(s);
    expect(s.state.device.deviceId, isNotNull);
    await s.dispatchAndWait(LogOutAction());
  }

  /// A fresh start of Studio on this computer, at the log-in page.
  Future<Store<AppState>> started() async {
    final s = store();
    await fill(s);
    await s.dispatchAndWait(LoadDeviceAction());
    return s;
  }
}

Future<void> fill(Store<AppState> s) async {
  await s.dispatchAndWait(SetGatewayAction(_gateway));
  await s.dispatchAndWait(SetUserAction(_user));
  await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
}

Future<void> _enable(Store<AppState> s) async {
  await s.dispatchAndWait(EnableDeviceAction(reason: 'turn on'));
}

void main() {
  group('the offer after a password login', () {
    test('is shown once per gateway and user, with the policy', () async {
      final c = _Computer();
      final s = await c.loggedIn();

      await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));

      expect(s.state.device.stage, UnlockStage.offer);
      expect(s.state.device.policy?.enabled, isTrue);
      expect((await c.records.read(_origin, _user)).offered, isTrue);

      // `Not now`, then the next login asks nothing.
      await s.dispatchAndWait(DeclineOfferAction());
      expect(s.state.device.stage, UnlockStage.none);
      await s.dispatchAndWait(LogOutAction());
      final again = await c.loggedIn();
      await again.dispatchAndWait(
        OfferDeviceAction(enable: () => _enable(again)),
      );
      expect(again.state.device.stage, UnlockStage.none);
      expect((await c.records.read(_origin, _user)).dontAsk, isFalse);
    });

    test("`Don't ask on this computer` is kept", () async {
      final c = _Computer();
      final s = await c.loggedIn();
      await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));

      await s.dispatchAndWait(DeclineOfferAction(dontAsk: true));

      expect(s.state.device.dontAsk, isTrue);
      expect((await c.records.read(_origin, _user)).dontAsk, isTrue);
    });

    test(
      'is not shown without a biometric, devices off or Remember off',
      () async {
        // No biometric: said once per computer. The log-in page said it
        // already (a remembered user), so the offer does not again.
        final none = _Computer(
          keys: FakeDeviceKey(availability: DeviceKeyAvailability.none),
        );
        final s = await none.loggedIn();
        expect(await none.records.noticed(), isTrue);
        await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));
        expect(s.state.device.stage, UnlockStage.none);

        // Not said on the page (no remembered user then): the offer's own
        // no-biometric form, once.
        final fresh = _Computer(
          keys: FakeDeviceKey(availability: DeviceKeyAvailability.none),
        );
        final f = fresh.store();
        await f.dispatchAndWait(LoadDeviceAction());
        await fill(f);
        await f.dispatchAndWait(LogInAction());
        await f.dispatchAndWait(OfferDeviceAction(enable: () => _enable(f)));
        expect(f.state.device.stage, UnlockStage.offer);
        expect(f.state.device.available, isFalse);
        await f.dispatchAndWait(DeclineOfferAction());
        await f.dispatchAndWait(LogOutAction());
        final again = await fresh.loggedIn();
        await again.dispatchAndWait(
          OfferDeviceAction(enable: () => _enable(again)),
        );
        expect(again.state.device.stage, UnlockStage.none);

        // Devices off at the gateway.
        final off = _Computer()
          ..login.info_ = const GatewayInfo(
            site: 'central',
            version: '0.1.0',
            tls: false,
          );
        final o = await off.loggedIn();
        await o.dispatchAndWait(OfferDeviceAction(enable: () => _enable(o)));
        expect(o.state.device.stage, UnlockStage.none);
      },
    );

    test('Use registers a key the gateway checked, then Welcome', () async {
      final c = _Computer();
      final s = await c.loggedIn();
      await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));

      await _enable(s);

      final d = s.state.device;
      expect(d.stage, UnlockStage.none);
      expect(d.deviceId, 'd1');
      expect(d.keyId, keyAlias(_origin, _user));
      expect(c.keys.has(d.keyId!), isTrue);
      final r = await c.records.read(_origin, _user);
      expect(r.usable, isTrue);
      expect(r.site, 'central');
      expect(c.gateway.records['d1']?.name, endsWith('Studio'));
      expect(c.keys.reasons, ['turn on'], reason: 'one prompt, the register');
    });

    test('a failure goes on to Welcome with a quiet error', () async {
      final c = _Computer();
      final s = await c.loggedIn();
      c.keys.answer = FakeAnswer.cancelled;

      final status = await s.dispatchAndWait(
        EnableDeviceAction(reason: 'turn on'),
      );

      expect(status.originalError, isA<UserException>());
      expect(s.state.device.stage, UnlockStage.none);
      expect(s.state.device.deviceId, isNull);
      expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
      expect(s.state.problems.toasts, isNotEmpty, reason: 'a quiet toast');
    });
  });

  group('unlock on start', () {
    test('a key shows Welcome back and logs in with it', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();

      expect(s.state.device.stage, UnlockStage.unlock);
      expect(s.state.device.keySite, 'central');

      final status = await s.dispatchAndWait(
        UnlockWithDeviceAction(reason: _reason),
      );

      expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
      expect(s.state.session.token, 'user:admin');
      expect(s.state.device.stage, UnlockStage.none);
      expect(c.gateway.logins, 1);
      expect(c.keys.reasons.last, _reason);
      expect(c.login.password, isNot('x'), reason: 'no password sent');
    });

    test('the prompt opens by itself once, never after a cancel', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      c.keys.answer = FakeAnswer.cancelled;
      final before = c.keys.reasons.length;

      await s.dispatchAndWait(
        UnlockWithDeviceAction(reason: _reason, auto: true),
      );
      await s.dispatchAndWait(
        UnlockWithDeviceAction(reason: _reason, auto: true),
      );

      expect(c.keys.reasons.length - before, 1);
      expect(s.state.device.stage, UnlockStage.fallback);
      // A press still prompts.
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      expect(c.keys.reasons.length - before, 2);
    });

    test(
      'cancel and lockout fall back to the password, the key kept',
      () async {
        for (final answer in [FakeAnswer.cancelled, FakeAnswer.lockout]) {
          final c = _Computer();
          await c.enrolled();
          final s = await c.started();
          c.keys.answer = answer;

          await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

          expect(s.state.device.stage, UnlockStage.fallback, reason: '$answer');
          expect(c.keys.has(keyAlias(_origin, _user)), isTrue);
          expect((await c.records.read(_origin, _user)).usable, isTrue);

          // The password login names the device, so `password_due` clears.
          await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
          await s.dispatchAndWait(LogInAction());
          expect(c.login.device, 'd1');
        }
      },
    );

    test('Use the password keeps the key and stops the auto prompt', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();

      await s.dispatchAndWait(UsePasswordAction());
      await s.dispatchAndWait(
        UnlockWithDeviceAction(reason: _reason, auto: true),
      );

      expect(s.state.device.stage, UnlockStage.fallback);
      expect(c.gateway.logins, 0);
    });

    test('changed fingerprints: key gone, the record removed after the login,'
        ' a new key when ticked', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      c.keys.invalidate(keyAlias(_origin, _user));

      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      expect(s.state.device.stage, UnlockStage.changed);
      expect(s.state.device.reEnable, isTrue);
      expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
      expect((await c.records.read(_origin, _user)).stale, isTrue);

      await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
      await s.dispatchAndWait(LogInAction());
      expect(c.login.device, isNull, reason: 'a stale key is not named');
      await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));

      expect(c.gateway.records.containsKey('d1'), isFalse, reason: 'removed');
      expect(s.state.device.deviceId, 'd2', reason: 'turned on again');
      expect(s.state.device.stage, UnlockStage.none);
    });

    test('each refusal of the gateway says its reason', () async {
      final cases = {
        'device_removed': UnlockRefusal.removed,
        'password_changed': UnlockRefusal.passwordChanged,
        'password_due': UnlockRefusal.passwordDue,
        'devices_off': UnlockRefusal.devicesOff,
      };
      for (final MapEntry(key: code, value: refusal) in cases.entries) {
        final c = _Computer();
        await c.enrolled();
        final s = await c.started();
        c.gateway.refuse = code;

        await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

        final d = s.state.device;
        expect(d.stage, UnlockStage.signedOut, reason: code);
        expect(d.refusal, refusal, reason: code);
        final kept = refusal == UnlockRefusal.passwordDue;
        expect(c.keys.has(keyAlias(_origin, _user)), kept, reason: code);
        expect(d.reEnable, refusal != UnlockRefusal.devicesOff, reason: code);
        expect(s.state.session.token, isNull, reason: code);
      }
    });

    test('a bare refusal: the gateway does not know the key', () async {
      final c = _Computer();
      await c.enrolled();
      c.gateway.records.clear();
      final s = await c.started();

      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      expect(s.state.device.stage, UnlockStage.signedOut);
      expect(s.state.device.refusal, UnlockRefusal.unknown);
      expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
    });

    test('devices turned off: the key goes before any prompt', () async {
      final c = _Computer();
      await c.enrolled();
      c.login.info_ = const GatewayInfo(
        site: 'central',
        version: '0.1.0',
        tls: false,
      );
      final before = c.keys.reasons.length;

      final s = await c.started();

      expect(s.state.device.stage, UnlockStage.signedOut);
      expect(s.state.device.refusal, UnlockRefusal.devicesOff);
      expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
      expect(c.keys.reasons.length, before);
    });

    test('an unreachable gateway: the key is not tried', () async {
      final c = _Computer();
      await c.enrolled();
      final down = _Computer(
        keys: c.keys,
        login: FakeLogin(
          session: c.login.session,
          answer: const GatewayProbe.noAnswer('timed out'),
        ),
      );
      final s = fakeStore(
        login: down.login,
        keys: c.keys,
        settings: c.settings,
      );
      await fill(s);
      await s.dispatchAndWait(LoadDeviceAction());
      final before = c.keys.reasons.length;

      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      expect(c.keys.reasons.length, before);
      expect(s.state.login.failure, LoginFailure.unreachable);
      expect(s.state.device.stage, UnlockStage.unlock);
    });

    test('no biometric: said once, then the password form', () async {
      final c = _Computer(
        keys: FakeDeviceKey(availability: DeviceKeyAvailability.none),
      );
      final first = await c.started();
      expect(first.state.device.stage, UnlockStage.noBiometrics);

      final second = await c.started();
      expect(second.state.device.stage, UnlockStage.none);
    });

    test('a log out keeps the key, so the next page unlocks again', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      await s.dispatchAndWait(LogOutAction());
      await s.dispatchAndWait(LoadDeviceAction());

      expect(s.state.device.keyId, isNotNull);
      expect(s.state.device.stage, UnlockStage.unlock);
    });
  });

  group('the step-up', () {
    Future<(Store<AppState>, _Computer)> guarded() async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      final api = c.login.session.api
        ..stepUp = c.gateway
        ..stepUpKeys.add('wy/central/sys/x');
      c.gateway.confirmed = false;
      expect(api.stepUp, isNotNull);
      return (s, c);
    }

    test('confirm with the device, then the same request again', () async {
      final (s, c) = await guarded();

      final set = depsOf(s).wyrm.set('wy/central/sys/x', const VInt(1));
      await pumpEventQueue();

      expect(s.state.device.stepUp, isNotNull);
      expect(s.state.device.stepUp!.passwordOnly, isFalse);
      expect(s.state.device.stepUp!.lines.single.key, 'wy/central/sys/x');
      await s.dispatchAndWait(ConfirmStepUpAction(reason: 'confirm'));
      await set;

      expect(s.state.device.stepUp, isNull);
      expect(c.gateway.confirms, 1);
      final sets = c.login.session.api.calls.where((x) => x.op == 'set');
      expect(sets, hasLength(2), reason: 'refused, then sent again');
    });

    test('a wrong password stays, the right one confirms', () async {
      final (s, c) = await guarded();
      final set = depsOf(s).wyrm.set('wy/central/sys/x', const VInt(1));
      await pumpEventQueue();

      await s.dispatchAndWait(ConfirmStepUpAction(reason: 'c', password: 'no'));
      expect(s.state.device.stepUp?.error, 'bad_password');
      await s.dispatchAndWait(
        ConfirmStepUpAction(reason: 'c', password: 'wyrm-demo-1'),
      );
      await set;

      expect(s.state.device.stepUp, isNull);
      expect(c.gateway.confirmed, isTrue);
    });

    test('cancel fails the request with the refusal', () async {
      final (s, _) = await guarded();
      final set = depsOf(s).wyrm.set('wy/central/sys/x', const VInt(1));
      await pumpEventQueue();

      s.dispatchSync(CancelStepUpAction());

      await expectLater(
        set,
        throwsA(
          isA<WyrmException>().having(
            (e) => e.code,
            'code',
            'confirm_required',
          ),
        ),
      );
      expect(s.state.device.stepUp, isNull);
    });

    test(
      'one dialog for two refused requests; staged changes are listed',
      () async {
        final (s, c) = await guarded();
        c.login.session.api.stepUpKeys.add('wy/central/sys/y');
        s.dispatchSync(
          AddChangesAction(
            IList(const [
              StagedChange(
                id: 'c1',
                op: 'Edit',
                key: 'wy/central/sys/x',
                field: 'value',
                to: '1',
                level: 'config',
                value: 1,
              ),
              StagedChange(
                id: 'c2',
                op: 'Edit',
                key: 'wy/central/sys/z',
                field: 'value',
                to: '2',
                value: 2,
              ),
            ]),
          ),
        );
        final apply = s.dispatchAndWait(ApplyChangesAction());
        final other = depsOf(s).wyrm.set('wy/central/sys/y', const VInt(3));
        await pumpEventQueue();

        final lines = s.state.device.stepUp!.lines;
        expect(lines.map((l) => l.level), ['config', 'write']);
        await s.dispatchAndWait(ConfirmStepUpAction(reason: 'c'));
        await apply;
        await other;

        expect(c.gateway.confirms, 1, reason: 'one dialog');
        expect(s.state.changes.view, isEmpty, reason: 'all applied');
      },
    );

    test('a user change over HTTP meets the step-up too', () async {
      final (s, c) = await guarded();
      c.login.session.api.stepUpKeys.add('user:ivan');

      final add = depsOf(s).session!.addUser('ivan', 'pw', ['operator']);
      await pumpEventQueue();
      expect(s.state.device.stepUp!.lines.single.text, 'add user ivan');
      await s.dispatchAndWait(ConfirmStepUpAction(reason: 'c'));
      await add;

      expect(c.login.session.userTable.keys, contains('ivan'));
      final adds = c.login.session.api.calls.where((x) => x.op == 'add_user');
      expect(adds, hasLength(2));
    });
  });

  group('the idle lock', () {
    test('locks, and the key unlocks the same session', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      final session = depsOf(s).rawSession;
      s
        ..dispatchSync(
          AddChangesAction(
            IList(const [
              StagedChange(
                id: 'c1',
                op: 'Edit',
                key: 'k',
                field: 'value',
                to: '1',
              ),
            ]),
          ),
        )
        ..dispatchSync(LockAction());
      expect(s.state.device.locked, isTrue);
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      expect(s.state.device.locked, isFalse);
      expect(depsOf(s).rawSession, same(session), reason: 'session kept');
      expect(s.state.session.token, isNotNull);
      expect(s.state.changes.view, ['c1'], reason: 'Review and apply kept');
      expect(c.gateway.logins, 2);
    });

    test('a cancelled prompt keeps the lock; the password opens it', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      s.dispatchSync(LockAction());
      c.keys.answer = FakeAnswer.cancelled;

      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      expect(s.state.device.locked, isTrue);

      await s.dispatchAndWait(UnlockWithPasswordAction('nope'));
      expect(s.state.device.locked, isTrue);
      expect(s.state.device.lockError, 'bad_password');
      await s.dispatchAndWait(UnlockWithPasswordAction('wyrm-demo-1'));
      expect(s.state.device.locked, isFalse);
    });

    test('a refusal while locked logs out and says why', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));
      s.dispatchSync(LockAction());
      c.gateway.refuse = 'password_changed';

      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      expect(s.state.session.token, isNull);
      expect(s.state.device.locked, isFalse);
      expect(s.state.device.stage, UnlockStage.signedOut);
      expect(s.state.device.refusal, UnlockRefusal.passwordChanged);
    });

    test('the delay is capped by the gateway and kept per user', () async {
      final c = _Computer()
        ..login.info_ = const GatewayInfo(
          site: 'central',
          version: '0.1.0',
          tls: false,
          devices: DevicePolicy(enabled: true, idleLockMaxMin: 15),
        );
      final s = await c.loggedIn();

      await s.dispatchAndWait(SetLockAfterAction(30));

      expect(s.state.device.lockAfter, 15);
      expect((await c.records.read(_origin, _user)).lockAfter, 15);
      expect(depsOf(s).idleLock.delay, const Duration(minutes: 15));
    });

    test('the clock locks after the delay and starts again on a touch', () {
      fakeAsync((time) {
        var idle = 0;
        final clock = IdleLockService(listener: _Count(() => idle++))
          ..arm(const Duration(minutes: 5));
        time.elapse(const Duration(minutes: 4));
        clock.touch();
        time.elapse(const Duration(minutes: 4));
        expect(idle, 0, reason: 'the touch started it again');
        time.elapse(const Duration(minutes: 1, seconds: 1));
        expect(idle, 1);
        clock.arm(Duration.zero);
        time.elapse(const Duration(hours: 1));
        expect(idle, 1, reason: 'off');
      });
    });

    test(
      "another user's login takes that user's record, not the page's",
      () async {
        final c = _Computer();
        // admin keeps a 15 min lock and Don't ask; ivan 5 min.
        await c.records.write(
          _origin,
          _user,
          const DeviceRecord(lockAfter: 15, dontAsk: true, offered: true),
        );
        await c.records.write(
          _origin,
          'ivan',
          const DeviceRecord(lockAfter: 5),
        );
        final s = await c.started();
        expect(s.state.device.lockAfter, 15);

        await s.dispatchAndWait(SetUserAction('ivan'));
        await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
        await s.dispatchAndWait(LogInAction());
        await s.dispatchAndWait(OfferDeviceAction(enable: () => _enable(s)));

        expect(s.state.device.lockAfter, 5);
        expect(s.state.device.dontAsk, isFalse);
        expect(s.state.device.stage, UnlockStage.offer, reason: "ivan's first");
        expect(depsOf(s).idleLock.delay, const Duration(minutes: 5));
      },
    );
  });

  group('Account › Security and Access › Users', () {
    test(
      'lists the devices; Turn off removes the key and the record',
      () async {
        final c = _Computer();
        await c.enrolled();
        final s = await c.started();
        await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

        await s.dispatchAndWait(RetrieveDevicesAction());
        expect(s.state.device.devices.single.thisDevice, isTrue);

        await s.dispatchAndWait(SetDeviceUnlockAction(on: false, reason: 'x'));

        expect(c.gateway.records, isEmpty);
        expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
        expect((await c.records.read(_origin, _user)).deviceId, isNull);
        expect(s.state.device.deviceId, isNull);
      },
    );

    test('the switch asks for the password when the gateway does', () async {
      final c = _Computer();
      final s = await c.loggedIn();
      c.gateway.passwordFresh = false;

      await s.dispatchAndWait(SetDeviceUnlockAction(on: true, reason: 'x'));
      expect(s.state.device.needPassword, isTrue);
      expect(s.state.device.deviceId, isNull);

      await s.dispatchAndWait(
        SetDeviceUnlockAction(on: true, reason: 'x', password: 'wyrm-demo-1'),
      );
      expect(s.state.device.needPassword, isFalse);
      expect(s.state.device.deviceId, isNotNull);
    });

    test("an admin's Remove leaves a tombstone; Forget deletes it", () async {
      final c = _Computer();
      final s = await c.loggedIn();
      c.gateway.records['x1'] = FakeDeviceRecord(
        'x1',
        'olena',
        'Pixel 8 · Studio',
        c.keys.publicKey('none') ?? (await c.keys.create('o')).publicKey,
      );

      await s.dispatchAndWait(RetrieveUserDevicesAction('olena'));
      expect(
        s.state.device.userDevices['olena']?.single.name,
        'Pixel 8 · Studio',
      );
      await s.dispatchAndWait(RemoveDeviceAction('x1', user: 'olena'));
      await pumpEventQueue();

      expect(c.gateway.records['x1']?.state, 'removed');
      expect(
        s.state.device.userDevices['olena']?.single.removedBy,
        'user:admin',
      );
      await s.dispatchAndWait(RemoveDeviceAction('x1', user: 'olena'));
      expect(c.gateway.records, isEmpty);
    });

    test('Sign out everywhere ends the session and the key here', () async {
      final c = _Computer();
      await c.enrolled();
      final s = await c.started();
      await s.dispatchAndWait(UnlockWithDeviceAction(reason: _reason));

      await s.dispatchAndWait(SignOutEverywhereAction());

      expect(c.gateway.signedOutEverywhere, 1);
      expect(s.state.session.token, isNull);
      expect(c.keys.has(keyAlias(_origin, _user)), isFalse);
      expect((await c.records.read(_origin, _user)).deviceId, isNull);
    });
  });
}

final class _Count implements IdleLockServiceListener {
  _Count(this.f);

  final void Function() f;

  @override
  void onIdle() => f();
}
