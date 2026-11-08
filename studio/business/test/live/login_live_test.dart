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
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/site/actions/retrieve_sites_action.dart';
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
    expect(s.state.session.token, user);
    expect(s.state.site.name, isNotEmpty);
    final deps = s.dependencies! as AppDependencies;
    final who = await deps.session!.me();
    final children = await deps.wyrm.children('wy/${who.site}/sys');
    expect(children.map((c) => c.name), contains('links'));
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

  test('RetrieveLinksAction lists the links of the site', () async {
    final s = store();
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction(user));
    await s.dispatchAndWait(SetPasswordAction(password));
    await s.dispatchAndWait(LogInAction());

    final status = await s.dispatchAndWait(RetrieveLinksAction());

    expect(status.isCompletedOk, isTrue, reason: '${status.originalError}');
    expect(s.state.links.view, isNotEmpty);
    expect(
      s.state.links.table.values.every((l) => l.driver.isNotEmpty),
      isTrue,
    );
    await (s.dependencies! as AppDependencies).detach();
  }, skip: skip);

  test('RetrieveSitesAction finds the brokers below and above', () async {
    final s = store();
    await s.dispatchAndWait(SetGatewayAction(gateway));
    await s.dispatchAndWait(SetUserAction(user));
    await s.dispatchAndWait(SetPasswordAction(password));
    await s.dispatchAndWait(LogInAction());

    await s.dispatchAndWait(RetrieveSitesAction());

    final sites = s.state.site.choices.map((c) => c.site).toList();
    expect(sites.first, s.state.site.name);
    expect(sites.length, greaterThan(1), reason: 'the demo is a chain: $sites');
    expect(SelectSite(s.state).levelOn('wy/${sites.first}/sys'), 'config');
    await (s.dependencies! as AppDependencies).detach();
  }, skip: skip);
}
