import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/load_device_action.dart';
import 'package:business/redux/device/actions/set_lock_after_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/device_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/lock_error.dart';
import 'package:models/refusal_code.dart';
import 'package:models/step_up_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// What the log-in page, the lock and the step-up read from the state and
/// from the gateway's refusals, typed (studio-rules §2, §8).
void main() {
  group('the idle lock is capped', () {
    test('by the gateway policy it knows', () async {
      final s = fakeStore();
      await _logIn(s);
      expect(s.state.device.policy?.idleLockMaxMin, 30);
      await s.dispatchAndWait(SetLockAfterAction(60));
      expect(s.state.device.lockAfter, 30);
    });

    test('at 30 while the policy is not known (an older wyrmd)', () async {
      // `/api/info` that Studio cannot read: no policy at all.
      final login = FakeLogin()..info_ = null;
      final s = fakeStore(login: login);
      await _logIn(s);
      expect(s.state.device.policy, isNull);

      await s.dispatchAndWait(SetLockAfterAction(60));
      expect(s.state.device.lockAfter, 30, reason: 'never no cap');

      await s.dispatchAndWait(SetLockAfterAction(15));
      expect(s.state.device.lockAfter, 15);
    });
  });

  group("the gateway's refusals, typed", () {
    WyrmException refused(String? code, [String message = 'refused']) =>
        WyrmException.of(Status.permissionDenied, message, code: code);

    test('the lock: the password, a named reason, else the message', () {
      expect(
        lockErrorOf(refused('bad_password')),
        const LockError.wrongPassword(),
      );
      expect(
        lockErrorOf(refused('too_many_devices')),
        const LockError.gateway(RefusalCode.tooManyDevices),
      );
      expect(
        lockErrorOf(refused('device_removed')),
        const LockError.gateway(RefusalCode.deviceRemoved),
      );
      expect(
        lockErrorOf(refused(null, 'session gone')),
        const LockError.refused('session gone'),
      );
      expect(
        lockErrorOf(refused('a_code_from_later', 'not yet known')),
        const LockError.refused('not yet known'),
        reason: 'a code this client does not know keeps the message',
      );
    });

    test('the step-up: the same, and the prompt that gave nothing', () {
      expect(
        stepUpRefusalOf(refused('bad_password')),
        const StepUpError.wrongPassword(),
      );
      expect(
        stepUpRefusalOf(refused('password_changed')),
        const StepUpError.gateway(RefusalCode.passwordChanged),
      );
      expect(
        stepUpRefusalOf(refused(null, 'unauthorized')),
        const StepUpError.refused('unauthorized'),
      );
    });

    test('every refusal code maps to its own reason', () {
      expect(
        {for (final r in GatewayRefusal.values) refusalCodeOf(r)},
        RefusalCode.values.toSet(),
      );
    });
  });

  group('Probe a range', () {
    test('the range and the port typed, else their defaults', () {
      final a = AppState.initial();
      final d = a.copyWith(
        login: a.login.copyWith(gateway: 'https://plant.local:9443'),
        discovery: a.discovery.copyWith(subnet: '10.0.7.0/24'),
      );
      expect(SelectDiscovery(d).rangeText, '10.0.7.0/24');
      expect(SelectDiscovery(d).defaultProbePort, 9443);
      expect(SelectDiscovery(d).portText, '9443');
      expect(SelectDiscovery(d).probePort, 9443);

      final typed = d.copyWith.discovery(
        range: '10.0.8.0/30',
        rangePort: '70000',
      );
      expect(SelectDiscovery(typed).rangeText, '10.0.8.0/30');
      expect(SelectDiscovery(typed).portText, '70000');
      expect(SelectDiscovery(typed).probePort, isNull, reason: 'not a port');

      final none = a.copyWith.login(gateway: '');
      expect(SelectDiscovery(none).defaultProbePort, 8446);
    });
  });
}

Future<void> _logIn(Store<AppState> s) async {
  await s.dispatchAndWait(SetGatewayAction('http://127.0.0.1:8445'));
  await s.dispatchAndWait(SetUserAction('admin'));
  await s.dispatchAndWait(SetPasswordAction('wyrm-demo-1'));
  await s.dispatchAndWait(LoadDeviceAction());
  final status = await s.dispatchAndWait(LogInAction());
  expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
}
