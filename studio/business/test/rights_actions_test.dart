// The rights check where actions use it: what is sent, staged and kept
// when the user's rights are missing. The first four failed on main
// 7ac1beee (written there with its string levels): apply sent the change
// in all three cases, and the value was staged at `write`. The last one
// passed on main too (`wyrm_client` refused the answer there already); it
// keeps a refused `/api/me` from leaving any right behind.
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/add_changes_action.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/staged_change.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// `/api/me` cleared, as before it is read: no `max`, no grants.
class _NoMe extends ReduxAction<AppState> {
  @override
  AppState reduce() =>
      state.copyWith.site(max: null, grants: const IListConst([]));
}

const _key = 'wy/central/downstream/m/sp';

const _change = StagedChange(
  id: 'c1',
  op: 'Edit',
  key: _key,
  field: 'value',
  to: '21.5',
  level: Perm.write,
  value: 21.5,
);

void main() {
  late FakeLogin login;
  late Store<AppState> s;

  Future<void> logIn(FakeSession session) async {
    login = FakeLogin(session: session);
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('olena'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  }

  List<String> sets() => [
    for (final c in login.session.api.calls)
      if (c.op == 'set') c.key,
  ];

  test('apply with no /api/me read sends nothing', () async {
    await logIn(FakeSession());
    s
      ..dispatchSync(_NoMe())
      ..dispatchSync(AddChangesAction(const IListConst([_change])));
    expect(s.state.site.max, isNull);

    await s.dispatchAndWait(ApplyChangesAction());

    expect(sets(), isEmpty);
    expect(s.state.changes.view, ['c1'], reason: 'kept, not applied');
  });

  test('apply for a user with no grant sends nothing', () async {
    await logIn(
      FakeSession(
        who: identityOf(
          subject: 'user:olena',
          site: 'central',
          roles: const ['viewer'],
          max: 'write',
          grants: const [],
        ),
      ),
    );
    s.dispatchSync(AddChangesAction(const IListConst([_change])));

    await s.dispatchAndWait(ApplyChangesAction());

    expect(sets(), isEmpty);
    expect(s.state.changes.view, ['c1']);
  });

  test('apply sends what the first matching grant reaches, not more', () async {
    // viewer first, then operator: the gateway signs `read` on
    // `downstream/**`, so a write there is not sent
    await logIn(
      FakeSession(
        who: identityOf(
          subject: 'user:olena',
          site: 'central',
          roles: const ['viewer', 'operator'],
          max: 'write',
          grants: const [
            ('wy/central/downstream/**', 'read'),
            ('wy/central/downstream/**', 'write'),
          ],
        ),
      ),
    );
    s.dispatchSync(AddChangesAction(const IListConst([_change])));

    await s.dispatchAndWait(ApplyChangesAction());

    expect(sets(), isEmpty);
  });

  test('a value whose meta names no level is not staged, and the user is '
      'told', () async {
    await logIn(FakeSession());
    login.session.api.metas[_key] = NodeMeta(ty: TypeCode.number);
    await s.dispatchAndWait(RetrieveNodeDetailAction(_key));

    final status = await s.dispatchAndWait(
      StageValueAction(_key, 21.5, from: '20'),
    );

    expect(s.state.changes.table, isEmpty);
    expect(status.originalError, isA<UserException>());
  });

  test(
    'a /api/me whose level is no level leaves no session and no rights',
    () async {
      await logIn(
        FakeSession(
          me: Value.from({
            'sub': 'user:eve',
            'site': 'central',
            'roles': ['operator'],
            'max': 'root',
            'exp': 0,
            'grants': [
              {'k': 'wy/**', 'p': 'config'},
            ],
          }),
        ),
      );

      expect(s.state.session.token, isNull);
      expect(s.state.site.max, isNull);
      expect(s.state.site.grants, isEmpty);
      final site = SelectSite(s.state);
      for (final p in Perm.values.where((p) => p != Perm.none)) {
        expect(site.can(p, 'wy/central/sys'), isFalse);
      }
    },
  );
}
