import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/links/actions/get_link_log_action.dart';
import 'package:business/redux/links/actions/remove_link_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/start_link_action.dart';
import 'package:business/redux/links/actions/update_link_params_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/quarantine/actions/approve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/set_admission_options_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  });

  test('RetrieveLinksAction reads each link by its meta', () async {
    api.children_['wy/central/sys/links'] = [Child('modbus', NodeMeta())];
    api.metas['wy/central/sys/links/modbus'] = NodeMeta(
      attr: {'driver': const VStr('modbus'), 'mode': const VStr('process')},
    );

    await s.dispatchAndWait(RetrieveLinksAction());

    final l = s.state.links.table['modbus']!;
    expect(l.driver, 'modbus');
    expect(l.mode, LinkMode.process);
    expect(s.state.links.view, ['modbus']);
  });

  test('Start runs the action on sys/links/<id>', () async {
    api.invokes['wy/central/sys/links/modbus ▸ start'] = [];

    final status = await s.dispatchAndWait(StartLinkAction('modbus'));

    expect(status.isCompletedOk, isTrue);
    expect(
      api.calls.last.toString(),
      contains('wy/central/sys/links/modbus ▸ start'),
    );
  });

  test('a refusal is a user error with the broker message', () async {
    api.errors['wy/central/sys/links/modbus ▸ remove'] = WyrmException.of(
      Status.permissionDenied,
      'needs config',
    );

    final status = await s.dispatchAndWait(RemoveLinkAction('modbus'));

    expect(status.originalError, isA<UserException>());
    expect(
      (status.originalError! as UserException).reason,
      contains('needs config'),
    );
  });

  test('get_log rows become lines', () async {
    api.invokes['wy/central/sys/links/modbus ▸ get_log'] = [
      Value.from([
        {'time': 't1', 'level': 'warn', 'message': 'cannot connect'},
        {'time': 't2', 'level': 'info', 'message': 'up'},
      ]),
    ];

    await s.dispatchAndWait(GetLinkLogAction('modbus'));

    expect(s.state.links.log, ['t1  WARN  cannot connect', 't2  INFO  up']);
  });

  test('Edit params stages an update, Apply runs it', () async {
    await s.dispatchAndWait(
      UpdateLinkParamsAction('modbus', '{"connections": {}}', from: 'rev 1'),
    );
    expect(s.state.changes.view, hasLength(1));
    final c = s.state.changes.table.values.single;
    expect((c.action, c.level, c.from), ('update', 'config', 'rev 1'));

    api.invokes['wy/central/sys/links/modbus ▸ update'] = [const VInt(2)];
    await s.dispatchAndWait(ApplyChangesAction());

    expect(s.state.changes.view, isEmpty);
    final update = api.calls.lastWhere((c) => c.op == 'invoke');
    expect(update.args?['params'], isA<VMap>());
  });

  test('Apply stops at the first refusal and keeps the rest', () async {
    await s.dispatchAndWait(SetAdmissionOptionsAction(holdUnknown: true));
    await s.dispatchAndWait(SetAdmissionOptionsAction(allowAll: true));
    api.errors['wy/central/sys/enable_quarantine'] = WyrmException.of(
      Status.permissionDenied,
      'no',
    );

    await s.dispatchAndWait(ApplyChangesAction());

    expect(s.state.changes.view, hasLength(2), reason: 'nothing after it ran');
    expect(s.state.changes.message, contains('permission_denied: no'));
    expect(api.calls.where((c) => c.op == 'set'), hasLength(1));
  });

  test(
    'quarantine entries come with their approve form; approve sends it',
    () async {
      api.children_['wy/central/sys/quarantine'] = [
        Child('plc-gw-7', NodeMeta()),
      ];
      api.metas['wy/central/sys/quarantine/plc-gw-7'] = NodeMeta(
        display: 'plc-gw-7',
        attr: {'kind': const VStr('link')},
        actions: {
          'approve': ActionMeta()
            ..params['name'] = ParamMeta(ty: TypeCode.string)
            ..params['group'] = ParamMeta(enumValues: ['engineer', 'operator']),
        },
      );
      await s.dispatchAndWait(RetrieveQuarantineAction());
      expect(s.state.quarantine.forms['plc-gw-7']!.map((p) => p.name), [
        'name',
        'group',
      ]);

      api.invokes['wy/central/sys/quarantine/plc-gw-7 ▸ approve'] = [];
      await s.dispatchAndWait(
        ApproveQuarantineAction('plc-gw-7', {'name': '', 'group': 'engineer'}),
      );

      expect(api.calls.last.args?['group'], const VStr('engineer'));
      expect(api.calls.last.args?['name'], isNull, reason: 'empty is left out');
      expect(s.state.quarantine.view, isEmpty);
    },
  );
}
