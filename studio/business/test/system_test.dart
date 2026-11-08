import 'package:async_redux/async_redux.dart';
import 'package:business/redux/access/actions/remove_user_action.dart';
import 'package:business/redux/access/actions/retrieve_access_action.dart';
import 'package:business/redux/access/actions/save_user_action.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/historian/actions/retrieve_historian_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test(
    'users, grants and the audit tail are read; a user is added and removed',
    () async {
      api
        ..invokes['wy/central/sys ▸ get_permissions'] = [
          Value.from([
            {
              'subject': 'operator',
              'path': 'wy/{site}/downstream/**',
              'level': 'write',
              'source': 'gateway',
            },
          ]),
        ]
        ..invokes['wy/central/sys/audit ▸ tail'] = [
          Value.from([
            {'time': 't1', 'who': 'user:admin', 'op': 'set', 'key': 'a'},
          ]),
        ];

      await s.dispatchAndWait(
        SaveUserAction(
          'olena',
          password: 'pw',
          roles: ['operator'],
          isNew: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await s.dispatchAndWait(RetrieveAccessAction());

      expect(s.state.access.users.single.name, 'olena');
      expect(s.state.access.users.single.roles, ['operator']);
      expect(s.state.access.grants.single.level, 'write');
      expect(s.state.access.audit.single, 't1  user:admin  set a');

      await s.dispatchAndWait(RemoveUserAction('olena'));
      expect(s.state.access.users, isEmpty);
      expect(login.session.userTable, isEmpty);
    },
  );

  test(
    'watch groups come with their settings and the keys they record',
    () async {
      api
        ..children_['wy/central/sys/history'] = [
          Child('rows_written', NodeMeta(ty: TypeCode.number)),
          Child('ahu2', NodeMeta()),
          Child('sinks', NodeMeta()),
        ]
        ..children_['wy/central/sys/history/ahu2'] = [
          Child('interval', NodeMeta(ty: TypeCode.number)),
          Child('w1', NodeMeta(display: 'wy/central/downstream/m/count')),
        ]
        ..initial['wy/central/sys/history/*/*'] = [
          const ValSample(
            'wy/central/sys/history/ahu2/logging_type',
            Sample(VStr('All Data'), t: 1),
          ),
          const ValSample(
            'wy/central/sys/history/ahu2/interval',
            Sample(VFloat(60), t: 1),
          ),
        ];

      await s.dispatchAndWait(RetrieveHistorianAction());

      final g = s.state.historian.groups.single;
      expect(g.name, 'ahu2');
      expect(g.loggingType, 'All Data');
      expect(g.interval, 60);
      expect(g.keys, ['wy/central/downstream/m/count']);
      expect(g.watchIds, ['w1']);
      expect(s.state.historian.selected, 'ahu2');
    },
  );
}
