import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_timeline_audit_action.dart';
import 'package:business/redux/assistant/actions/set_chip_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/tasks/actions/set_selected_task_action.dart';
import 'package:business/wyrm/context_keys.dart';
import 'package:business/wyrm/mappers/agent_task_mapper.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _agent = 'wy/central/downstream/agent';
const _valve = 'wy/central/downstream/modbus/tcp/plc1/valve';

/// Spec `assistant.md` §5 and ADR 0049 amendment 2: what the model found,
/// the drawer's timeline marks, and the keys an `@` chip may name.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  Future<void> logIn(FakeLogin login) async {
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
  }

  test('the findings of a record, in order; an older record has none', () {
    final t = agentTaskOf(
      't-1',
      Value.from({
        'state': 'done',
        'plan': <Object?>[],
        'findings': [
          {'key': 'wy/central/downstream/modbus/tcp', 'label': 'tcp'},
          {'key': _valve, 'label': 'valve', 'detail': 'bad since 03:12'},
        ],
      }),
    );
    expect(
      [for (final f in t.findings) (f.key, f.label, f.detail)],
      [
        ('wy/central/downstream/modbus/tcp', 'tcp', ''),
        (_valve, 'valve', 'bad since 03:12'),
      ],
    );
    final old = agentTaskOf(
      't-0',
      Value.from({'state': 'done', 'plan': <Object?>[]}),
    );
    expect(old.findings, isEmpty);
  });

  test(
    'a new finding moves the public value: the record is read again',
    () async {
      await logIn(FakeLogin());
      api
        ..children_['wy/central/sys/links'] = [Child('agent', NodeMeta())]
        ..metas['wy/central/sys/links/agent'] = NodeMeta(
          attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
        )
        ..metas[_agent] = NodeMeta()
        ..docs['$_agent/tasks/t-1 ~state'] = Value.from({
          'state': 'planning',
          'plan': <Object?>[],
        });
      await s.dispatchAndWait(RetrieveLinksAction());
      await s.dispatchAndWait(RetrieveAgentAction());
      s.dispatchSync(SetSelectedTaskAction('t-1'));
      int reads() => api.calls.where((c) => c.op == 'doc').length;
      Future<void> val(Map<String, Object?> v) async {
        api.subs['$_agent/tasks/*']!.add(
          ValSample('$_agent/tasks/t-1', Sample(Value.from(v), t: 1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await val({'state': 'planning', 'step': 0, 'of': 0});
      final before = reads();
      await val({'state': 'planning', 'step': 0, 'of': 0, 'findings': 1});
      expect(reads(), before + 1);
      await val({'state': 'planning', 'step': 0, 'of': 0, 'findings': 1});
      expect(reads(), before + 1, reason: 'nothing moved');
    },
  );

  test('a context key is a plain node key of the site on screen', () {
    const root = 'wy/central';
    expect(
      contextKey(root, 'downstream/modbus/tcp'),
      'wy/central/downstream/modbus/tcp',
    );
    expect(contextKey(root, ' wy/central/storage/a/ '), 'wy/central/storage/a');
    for (final bad in [
      '',
      'wy/plant/downstream/x',
      'wy/centralx/a',
      'downstream/x/~val',
      'downstream/*/p',
      'downstream//p',
      'downstream/x?y',
      'wy',
    ]) {
      expect(contextKey(root, bad), isNull, reason: bad);
    }
    expect(contextKey(null, 'downstream/x'), isNull);
  });

  test('at most 16 chips, the agent link takes no more', () async {
    await logIn(FakeLogin());
    for (var i = 0; i < 20; i++) {
      s.dispatchSync(SetChipAction('wy/central/downstream/m/p$i'));
    }
    expect(s.state.assistant.chips, hasLength(maxContextKeys));
    s
      ..dispatchSync(SetChipAction('wy/central/downstream/m/p0', on: false))
      ..dispatchSync(SetChipAction('wy/central/downstream/m/p19'));
    expect(s.state.assistant.chips.last, 'wy/central/downstream/m/p19');
  });

  FakeLogin engineer() => FakeLogin(
    session: FakeSession(
      who: const WhoAmI(
        subject: 'user:olena',
        site: 'central',
        roles: ['engineer'],
        max: 'config',
        grants: [('wy/central/**', 'config')],
      ),
    ),
  );

  group('the timeline marks', () {
    List<Value> tail() => [
      Value.from([
        {
          't': 2000,
          'op': 'invoke',
          'key': '$_valve/~act/edit',
          'sub': 'user:ivan',
        },
        {
          't': 3000,
          'op': 'set',
          'key': '$_valve/~set',
          'sub': 'user:olena',
          'status': 0x22,
        },
        // another point, and a key that only starts like it
        {
          't': 4000,
          'op': 'set',
          'key': '${_valve}2/~set',
          'sub': 'user:ivan',
        },
      ]),
    ];

    test('are the audit records of the point, newest first', () async {
      await logIn(engineer());
      api.invokes['wy/central/sys/audit ▸ tail'] = tail();
      s.dispatchSync(SelectPointAction(_valve));
      await s.dispatchAndWait(RetrieveTimelineAuditAction(_valve));
      expect(s.state.assistant.timelineKey, _valve);
      expect(
        [
          for (final a in s.state.assistant.timelineAudit)
            (a.who, a.op, a.status),
        ],
        [('user:olena', 'set', 0x22), ('user:ivan', 'invoke', 0)],
      );
      // Explorer › Audit keeps its own records
      expect(s.state.nodes.audit, isEmpty);
    });

    test('of a point no longer selected are dropped', () async {
      await logIn(engineer());
      api.invokes['wy/central/sys/audit ▸ tail'] = tail();
      s.dispatchSync(SelectPointAction('${_valve}2'));
      await s.dispatchAndWait(RetrieveTimelineAuditAction(_valve));
      expect(s.state.assistant.timelineKey, isNull);
      expect(s.state.assistant.timelineAudit, isEmpty);
    });

    test('are not read without config on sys/audit', () async {
      await logIn(
        FakeLogin(
          session: FakeSession(
            who: const WhoAmI(
              subject: 'user:op',
              site: 'central',
              roles: ['operator'],
              max: 'write',
              grants: [('wy/central/downstream/**', 'write')],
            ),
          ),
        ),
      );
      api.invokes['wy/central/sys/audit ▸ tail'] = tail();
      s.dispatchSync(SelectPointAction(_valve));
      await s.dispatchAndWait(RetrieveTimelineAuditAction(_valve));
      expect(api.calls.where((c) => c.action == 'tail'), isEmpty);
      expect(s.state.assistant.timelineKey, _valve);
      expect(s.state.assistant.timelineAudit, isEmpty);
    });
  });
}
