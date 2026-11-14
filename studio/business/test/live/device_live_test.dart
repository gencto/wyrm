// The device unlock against a real gateway (ADR 0050):
// crates/wyrm-gateway/examples/gateway_dev.rs with the step-up on and a
// 2 s freshness. Runs only when the example is built and named:
//
//   cargo build -p wyrm-gateway --example gateway_dev
//   WYRM_GATEWAY_DEV=$PWD/target/debug/examples/gateway_dev \
//     flutter test test/live/device_live_test.dart
//
// The key is `FakeDeviceKey`: real P-256 signatures the gateway checks.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/device/actions/confirm_step_up_action.dart';
import 'package:business/redux/device/actions/enable_device_action.dart';
import 'package:business/redux/device/actions/load_device_action.dart';
import 'package:business/redux/device/actions/lock_action.dart';
import 'package:business/redux/device/actions/offer_device_action.dart';
import 'package:business/redux/device/actions/retrieve_devices_action.dart';
import 'package:business/redux/device/actions/unlock_with_device_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/session/actions/log_out_action.dart';
import 'package:device_key/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

void main() {
  final bin = Platform.environment['WYRM_GATEWAY_DEV'];
  final skip = bin == null ? 'WYRM_GATEWAY_DEV not set' : null;

  late Process server;
  late String gateway;
  final settings = InMemoryKeyValueStorage();
  final keys = FakeDeviceKey();

  setUpAll(() async {
    if (bin == null) {
      return;
    }
    server = await Process.start(bin, [
      '--step-up',
      'config',
      '--fresh-s',
      '2',
    ]);
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    final port = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('PORT='))
        .timeout(const Duration(seconds: 30));
    gateway = 'http://127.0.0.1:${port.substring(5)}';
  });

  tearDownAll(() async {
    if (bin == null) {
      return;
    }
    server.stdin.writeln('quit');
    await server.stdin.close();
    await server.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        server.kill();
        return -1;
      },
    );
  });

  Future<Store<AppState>> page() async {
    final s = Store<AppState>(
      initialState: AppState.initial(),
      dependencies: (s) => AppDependencies(s, settings, deviceKey: keys),
    );
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(LoadDeviceAction());
    return s;
  }

  AppDependencies deps(Store<AppState> s) => s.dependencies! as AppDependencies;

  test('register, device login, idle unlock, step-up, a refusal', () async {
    // A password login, then the offer: Use registers a key the gateway
    // checks (it signs the register nonce).
    final s = await page();
    expect(s.state.device.policy?.stepUp, 'config');
    await s.dispatchAndWait(SetPasswordAction('admin password'));
    final login = await s.dispatchAndWait(LogInAction());
    expect(login.isCompletedOk, isTrue, reason: '${login.originalError}');
    Future<void> enable() =>
        s.dispatchAndWait(EnableDeviceAction(reason: 'turn on'));
    await s.dispatchAndWait(OfferDeviceAction(enable: enable));
    expect(s.state.device.stage, UnlockStage.offer);
    final on = await s.dispatchAndWait(EnableDeviceAction(reason: 'turn on'));
    expect(on.isCompletedOk, isTrue, reason: '${on.originalError}');
    final id = s.state.device.deviceId;
    expect(id, isNotNull);
    await s.dispatchAndWait(RetrieveDevicesAction());
    expect(s.state.device.devices.map((d) => d.id), contains(id));
    await s.dispatchAndWait(LogOutAction());

    // A new start: Welcome back, the key logs in.
    final again = await page();
    expect(again.state.device.stage, UnlockStage.unlock);
    final unlocked = await again.dispatchAndWait(
      UnlockWithDeviceAction(reason: 'sign in'),
    );
    expect(unlocked.isCompletedOk, isTrue, reason: '${unlocked.originalError}');
    expect(again.state.session.token, isNotNull);
    final children = await deps(again).wyrm.children('wy/test/downstream');
    expect(children.map((c) => c.name), contains('mock'));

    // The idle lock: the key unlocks and the session stays.
    final kept = deps(again).rawSession;
    again.dispatchSync(LockAction());
    await again.dispatchAndWait(UnlockWithDeviceAction(reason: 'unlock'));
    expect(again.state.device.locked, isFalse);
    expect(deps(again).rawSession, same(kept));

    // The step-up: after the 2 s of freshness a user change is refused
    // with `confirm_required`; the key confirms; the same call goes again.
    await Future<void>.delayed(const Duration(seconds: 3));
    final add = deps(again).session!.addUser('ivan', 'ivan password 1', [
      'operator',
    ]);
    for (var i = 0; i < 50 && again.state.device.stepUp == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(again.state.device.stepUp, isNotNull, reason: 'confirm_required');
    final confirmed = await again.dispatchAndWait(
      ConfirmStepUpAction(reason: 'confirm'),
    );
    expect(confirmed.isCompletedOk, isTrue);
    await add;
    final users = await deps(again).session!.users();
    expect(users.map((u) => u.name), contains('ivan'));

    // A refusal with a code: Sign out everywhere moves the generation, so
    // the key hears `password_changed` and is deleted.
    await deps(again).rawSession!.signOutEverywhere();
    await again.dispatchAndWait(LogOutAction());
    final third = await page();
    expect(third.state.device.stage, UnlockStage.unlock);
    await third.dispatchAndWait(UnlockWithDeviceAction(reason: 'sign in'));
    expect(third.state.device.stage, UnlockStage.signedOut);
    expect(third.state.device.refusal, UnlockRefusal.passwordChanged);
    expect(third.state.session.token, isNull);
    expect(keys.has(third.state.device.keyId ?? 'none'), isFalse);
  }, skip: skip);
}
