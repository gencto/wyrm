import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/broker_update/actions/close_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/open_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/rollback_broker_update_action.dart';
import 'package:business/redux/broker_update/actions/set_confirm_action.dart';
import 'package:business/redux/broker_update/actions/update_broker_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _sys = 'wy/central/sys';

/// ADR 0048 §2 (not built in the broker): the two actions of the broker
/// update dialog against a fake session, with the names the ADR gives.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    final login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  test('update sends the version and the site name as typed', () async {
    api.invokes['$_sys ▸ update'] = [const VMap({})];
    s
      ..dispatchSync(OpenBrokerUpdateAction())
      ..dispatchSync(SetConfirmAction('central'));
    expect(s.state.brokerUpdate.stage, 'review');

    final status = await s.dispatchAndWait(UpdateBrokerAction('0.2.0'));

    expect(status.isCompletedOk, isTrue);
    final call = api.calls.lastWhere((c) => c.op == 'invoke');
    expect(call.key, _sys);
    expect(call.action, 'update');
    expect(call.args!['version'], const VStr('0.2.0'));
    expect(call.args!['confirm_site'], const VStr('central'));
    expect(s.state.brokerUpdate.stage, 'follow');
  });

  test('a refused update stays on the review', () async {
    api.errors['$_sys ▸ update'] = WyrmException.of(
      Status.invalidParameter,
      'confirm_site: not this site',
    );
    s.dispatchSync(OpenBrokerUpdateAction());

    final status = await s.dispatchAndWait(UpdateBrokerAction('0.2.0'));

    expect(status.isCompletedFailed, isTrue);
    expect(s.state.brokerUpdate.stage, 'review');
  });

  test('roll back calls rollback_update and follows', () async {
    api.invokes['$_sys ▸ rollback_update'] = [];
    s.dispatchSync(OpenBrokerUpdateAction(follow: true));

    await s.dispatchAndWait(RollbackBrokerUpdateAction());

    expect(api.calls.last.action, 'rollback_update');
    expect(s.state.brokerUpdate.stage, 'follow');
  });

  test('Close forgets the dialog and what was typed', () {
    s
      ..dispatchSync(OpenBrokerUpdateAction())
      ..dispatchSync(SetConfirmAction('central'))
      ..dispatchSync(CloseBrokerUpdateAction());
    expect(s.state.brokerUpdate.stage, isNull);
    expect(s.state.brokerUpdate.confirm, '');
  });
}
