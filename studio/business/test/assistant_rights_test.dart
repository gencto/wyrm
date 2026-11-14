import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_secrets_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/links/actions/retrieve_link_history_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/open_trend_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/staged_change.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

/// Spec `assistant.md` §2 step 6: what the agent may do, its params staged
/// as an update of `sys/links/<agent>`, its secret names, the drawer over
/// Explorer and the trend of a point.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;
  const agent = 'wy/central/downstream/agent';
  const links = 'wy/central/sys/links/agent';

  Future<void> logIn({
    List<(String, String)> grants = const [('wy/central/**', 'config')],
  }) async {
    final login = FakeLogin(
      session: FakeSession(
        who: WhoAmI(
          subject: 'user:olena',
          site: 'central',
          roles: const ['engineer'],
          max: grants.any((g) => g.$2 == 'config') ? 'config' : 'write',
          grants: grants,
        ),
      ),
    );
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('olena'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    api
      ..children_['wy/central/sys/links'] = [Child('agent', NodeMeta())]
      ..metas[links] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas[agent] = NodeMeta(
        cfg: {
          'require_approval': const VStr('write'),
          'allowed_prefixes': Value.from([
            'wy/central/downstream/modbus',
            'wy/central/storage',
          ]),
          'api_key_ref': const VStr('anthropic_api_key'),
          'api_base': const VStr('https://api.anthropic.com'),
        },
      );
    await s.dispatchAndWait(RetrieveLinksAction());
    await s.dispatchAndWait(RetrieveAgentAction());
  }

  test('the prefixes are kept as a list', () async {
    await logIn();
    expect(s.state.assistant.prefixes, [
      'wy/central/downstream/modbus',
      'wy/central/storage',
    ]);
    expect(s.state.assistant.cfg['api_base'], 'https://api.anthropic.com');
  });

  void history(String key, Map<String, Object?> params, {int rev = 3}) =>
      api.invokes['$key ▸ history'] = [
        Value.from([
          {'rev': rev, 'params': params},
        ]),
      ];

  StagedChange staged() => s.state.changes.table['params:$links']!;

  test('a param is staged as an update of the whole params, built on the '
      'one already staged', () async {
    await logIn();
    history(links, {
      'model': 'claude-sonnet-5-5',
      'require_approval': 'write',
      'allowed_prefixes': ['wy/central/downstream/modbus'],
    });

    await s.dispatchAndWait(StageAgentParamAction.mode('config'));
    await s.dispatchAndWait(
      StageAgentParamAction.addPrefix('wy/central/storage'),
    );

    final c = staged();
    expect((c.key, c.action, c.level), (links, 'update', 'config'));
    expect(c.args['params'], {
      'model': 'claude-sonnet-5-5',
      'require_approval': 'config',
      'allowed_prefixes': [
        'wy/central/downstream/modbus',
        'wy/central/storage',
      ],
    });
    // the history was read once: the second edit built on the first
    expect(api.calls.where((c) => c.action == 'history'), hasLength(1));
    // nothing is sent before Review applies it
    expect(api.calls.where((c) => c.action == 'update'), isEmpty);
  });

  test('two prefix edits in a row: the second keeps the first, and the '
      'panel shows the list as staged (review item 1)', () async {
    await logIn();
    history(links, {
      'allowed_prefixes': ['A', 'B', 'C'],
    });

    await s.dispatchAndWait(StageAgentParamAction.removePrefix('A'));
    expect(_Reader(s.state).agentParams.prefixes, ['B', 'C']);
    await s.dispatchAndWait(StageAgentParamAction.removePrefix('B'));

    expect(staged().args['params'], {
      'allowed_prefixes': ['C'],
    });
    expect(_Reader(s.state).agentParams.prefixes, ['C']);
  });

  test('a mode staged, then picked back: the update is unstaged (review '
      'item 1)', () async {
    await logIn();
    history(links, {'require_approval': 'write', 'model': 'm'});

    await s.dispatchAndWait(StageAgentParamAction.mode('config'));
    expect(_Reader(s.state).agentParams.mode, 'config');
    await s.dispatchAndWait(StageAgentParamAction.mode('write'));

    expect(s.state.changes.table, isEmpty);
    expect(_Reader(s.state).agentParams.mode, 'write');
  });

  test('the same link id on another site is never the base (review item '
      '2)', () async {
    await logIn();
    history(links, {
      'api_base': 'https://central.example',
      'allowed_prefixes': ['wy/central/downstream/modbus'],
    });
    await s.dispatchAndWait(StageAgentParamAction.mode('config'));

    // plant has an agent link of the same id
    const plantLinks = 'wy/plant/sys/links/agent';
    api
      ..children_['wy/plant/sys/links'] = [Child('agent', NodeMeta())]
      ..metas[plantLinks] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas['wy/plant/downstream/agent'] = NodeMeta(cfg: {});
    history(plantLinks, {
      'api_base': 'https://plant.example',
      'allowed_prefixes': ['wy/plant/downstream/s7'],
    }, rev: 8);
    s.dispatchSync(ViewSiteAction('plant'));
    await s.dispatchAndWait(RetrieveLinksAction());
    await s.dispatchAndWait(RetrieveAgentAction());
    await s.dispatchAndWait(StageAgentParamAction.mode('never'));

    final plant = s.state.changes.table['params:$plantLinks']!;
    expect(plant.key, plantLinks);
    expect(plant.args['params'], {
      'api_base': 'https://plant.example',
      'allowed_prefixes': ['wy/plant/downstream/s7'],
      'require_approval': 'never',
    });
    // central's staged update is still its own
    expect(
      (staged().args['params']! as Map)['api_base'],
      'https://central.example',
    );
    expect(s.state.changes.view, hasLength(2));
  });

  test('the review card names each param that changes, what it was and '
      'what it will be (review item 3)', () async {
    await logIn();
    history(links, {
      'model': 'm',
      'require_approval': 'write',
      'allowed_prefixes': ['A', 'B'],
    }, rev: 4);

    await s.dispatchAndWait(StageAgentParamAction.mode('config'));
    await s.dispatchAndWait(StageAgentParamAction.removePrefix('A'));

    final c = staged();
    expect(c.field, 'params · require_approval, allowed_prefixes');
    expect(c.from, 'rev 4: require_approval write; allowed_prefixes A, B');
    expect(c.to, 'require_approval config; allowed_prefixes B');
  });

  test(
    'nothing is staged when the params of the agent cannot be read',
    () async {
      await logIn();
      // the Links tab left another link's revisions in the one list
      api.invokes['wy/central/sys/links/modbus ▸ history'] = [
        Value.from([
          {
            'rev': 9,
            'params': {'connections': <Object?>[]},
          },
        ]),
      ];
      await s.dispatchAndWait(RetrieveLinkHistoryAction('modbus'));
      api.errors['$links ▸ history'] = WyrmException.of(
        Status.permissionDenied,
        'needs config',
      );

      final failed = await s.dispatchAndWait(
        StageAgentParamAction.mode('config'),
      );
      expect(failed.originalError, isA<UserException>());
      expect(s.state.changes.table, isEmpty);

      // a history without a revision is no base either
      api
        ..errors.remove('$links ▸ history')
        ..invokes['$links ▸ history'] = [Value.from(<Object?>[])];
      final empty = await s.dispatchAndWait(
        StageAgentParamAction.mode('config'),
      );
      expect(empty.originalError, isA<UserException>());
      expect(s.state.changes.table, isEmpty);
    },
  );

  test('the secret names of another agent are not kept', () async {
    await logIn();
    api.invokes['$links ▸ secrets'] = [
      Value.from(['anthropic_api_key']),
    ];
    await s.dispatchAndWait(RetrieveAgentSecretsAction());
    expect(s.state.assistant.secrets, isNotNull);
    // the same agent read again keeps them
    await s.dispatchAndWait(RetrieveAgentAction());
    expect(s.state.assistant.secrets, isNotNull);

    // another site's agent: not known until read for it
    api
      ..children_['wy/plant/sys/links'] = [Child('agent', NodeMeta())]
      ..metas['wy/plant/sys/links/agent'] = NodeMeta(
        attr: {'driver': const VStr('agent'), 'mode': const VStr('embedded')},
      )
      ..metas['wy/plant/downstream/agent'] = NodeMeta(cfg: {});
    s.dispatchSync(ViewSiteAction('plant'));
    await s.dispatchAndWait(RetrieveLinksAction());
    await s.dispatchAndWait(RetrieveAgentAction());
    expect(s.state.assistant.agent, 'wy/plant/downstream/agent');
    expect(s.state.assistant.secrets, isNull);
  });

  test('the secret names say whether the API key is set; without config '
      'they stay unknown', () async {
    await logIn();
    api.invokes['$links ▸ secrets'] = [
      Value.from(['anthropic_api_key', 'agent_key']),
    ];
    await s.dispatchAndWait(RetrieveAgentSecretsAction());
    expect(s.state.assistant.secrets, {'anthropic_api_key', 'agent_key'});

    await logIn(grants: const [('wy/central/**', 'write')]);
    await s.dispatchAndWait(RetrieveAgentSecretsAction());
    expect(s.state.assistant.secrets, isNull);
    expect(api.calls.where((c) => c.action == 'secrets'), isEmpty);
  });

  test('the drawer opens with the Explorer selection as a chip', () async {
    await logIn();
    s
      ..dispatchSync(SelectNodeAction('wy/central/downstream/modbus/tcp/plc1'))
      ..dispatchSync(SetDrawerAction.toggle());
    expect(s.state.assistant.drawer, isTrue);
    expect(s.state.assistant.chips, ['wy/central/downstream/modbus/tcp/plc1']);
    s.dispatchSync(SetDrawerAction.toggle());
    expect(s.state.assistant.drawer, isFalse);
  });

  test('the trend of a point opens in Explorer: its node, the point, the '
      'History tab', () async {
    await logIn();
    s.dispatchSync(OpenTrendAction('wy/central/downstream/modbus/tcp/ahu2/sp'));
    expect(
      s.state.nodes.selectedNode,
      'wy/central/downstream/modbus/tcp/ahu2',
    );
    expect(s.state.nodes.point, 'wy/central/downstream/modbus/tcp/ahu2/sp');
    expect(s.state.nodes.tab, 'history');
  });
}

class _Reader with Selectors {
  _Reader(this.state);

  @override
  final AppState state;
}
