import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_action.dart';
import 'package:business/redux/assistant/actions/retrieve_agent_secrets_action.dart';
import 'package:business/redux/assistant/actions/set_drawer_action.dart';
import 'package:business/redux/assistant/actions/stage_agent_param_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/open_trend_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/wyrm/session.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('a param is staged as an update of the whole params, built on the '
      'one already staged', () async {
    await logIn();
    api.invokes['$links ▸ history'] = [
      Value.from([
        {
          'rev': 3,
          'params': {
            'model': 'claude-sonnet-5-5',
            'require_approval': 'write',
            'allowed_prefixes': ['wy/central/downstream/modbus'],
          },
        },
      ]),
    ];

    await s.dispatchAndWait(
      StageAgentParamAction('require_approval', 'config'),
    );
    await s.dispatchAndWait(
      StageAgentParamAction('allowed_prefixes', ['wy/central/storage']),
    );

    final c = s.state.changes.table['params:agent']!;
    expect(
      (c.key, c.action, c.level, c.from),
      (
        links,
        'update',
        'config',
        'rev 3',
      ),
    );
    expect(c.args['params'], {
      'model': 'claude-sonnet-5-5',
      'require_approval': 'config',
      'allowed_prefixes': ['wy/central/storage'],
    });
    // the history was read once: the second edit built on the first
    expect(api.calls.where((c) => c.action == 'history'), hasLength(1));
    // nothing is sent before Review applies it
    expect(api.calls.where((c) => c.action == 'update'), isEmpty);
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
