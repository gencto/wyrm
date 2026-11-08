// Runs against a real gateway only when one is named:
//
//   WYRM_LIVE_GATEWAY=http://127.0.0.1:8445 WYRM_LIVE_PASSWORD=wyrm-demo-1 \
//     flutter test test/live
//
// (examples/demo/run.sh starts three.) Without the variables it is skipped.
import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:business/dependencies.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage/storage.dart';

void main() {
  final gateway = Platform.environment['WYRM_LIVE_GATEWAY'];
  final user = Platform.environment['WYRM_LIVE_USER'] ?? 'admin';
  final password = Platform.environment['WYRM_LIVE_PASSWORD'] ?? 'wyrm-demo-1';
  final skip = gateway == null ? 'WYRM_LIVE_GATEWAY not set' : null;

  Store<AppState> store() => Store<AppState>(
    initialState: AppState.initial(),
    dependencies: (s) => AppDependencies(s, InMemoryKeyValueStorage()),
  );

  test('logs in to the gateway and lists the site', () async {
    final s = store();
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction(user));
    await s.dispatchAndWait(SetPasswordAction(password));

    final status = await s.dispatchAndWait(LogInAction());

    expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
    expect(s.state.session.token, startsWith('user:'));
    final deps = s.dependencies! as AppDependencies;
    final who = await deps.session!.me();
    final children = await deps.wyrm.children('wy/${who.site}');
    expect(children.map((c) => c.name), contains('downstream'));
    await deps.detach();
  }, skip: skip);

  test('a wrong password is refused', () async {
    final s = store();
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction(user));
    await s.dispatchAndWait(SetPasswordAction('not-the-password'));

    final status = await s.dispatchAndWait(LogInAction());

    expect(status.originalError, isA<UserException>());
    expect(s.state.session.token, isNull);
  }, skip: skip);
}
