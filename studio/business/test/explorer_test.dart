import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/stage_invoke_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
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

  test('selecting a node opens its parents and lists it live', () async {
    const dev = 'wy/central/downstream/modbus/line1/ahu1';
    api.metas[dev] = NodeMeta(
      actions: {'read_device_id': ActionMeta()..level = Perm.read},
      cfg: {'unit': const VInt(1)},
    );

    s.dispatchSync(SelectNodeAction(dev));
    await Future<void>.delayed(Duration.zero);

    expect(s.state.nodes.selectedNode, dev);
    expect(
      s.state.nodes.expanded,
      containsAll([
        'wy/central/downstream',
        'wy/central/downstream/modbus',
        'wy/central/downstream/modbus/line1',
      ]),
    );
    expect(
      api.calls.where((c) => c.op == 'list').map((c) => c.key),
      contains(dev),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final d = s.state.nodes.detail[dev]!;
    expect(d.actions.single.level, 'read');
    expect(d.cfg['unit'], '1');
  });

  test('closing a node closes the lists under it', () {
    s
      ..dispatchSync(ToggleNodeAction('wy/central/downstream', open: true))
      ..dispatchSync(ToggleNodeAction('wy/central/downstream/mock', open: true))
      ..dispatchSync(ToggleNodeAction('wy/central/downstream'));

    expect(s.state.nodes.expanded, isEmpty);
    expect(depsOf(s).treeWatch.open_, isEmpty);
  });

  test(
    'a value edit is staged at the level the point asks, then set',
    () async {
      s.dispatchSync(
        StageValueAction('wy/central/downstream/m/sp', 21.5, from: '20'),
      );

      final c = s.state.changes.table.values.single;
      expect(
        (c.key, c.value, c.from, c.to, c.level),
        ('wy/central/downstream/m/sp', 21.5, '20', '21.5', 'write'),
      );

      await s.dispatchAndWait(ApplyChangesAction());
      expect(api.calls.last.op, 'set');
      expect(api.calls.last.value, const VFloat(21.5));
    },
  );

  test(
    'a config action is staged with its arguments, empty ones left out',
    () {
      s.dispatchSync(
        StageInvokeAction('wy/central/downstream/m/dev', 'add_point', {
          'name': 't3',
          'addr': 7,
          'unit': '',
        }),
      );

      final c = s.state.changes.table.values.single;
      expect(c.op, 'Add');
      expect(c.action, 'add_point');
      expect(c.args.unlock, {'name': 't3', 'addr': 7});
    },
  );

  test('a run-now action keeps its answer rows', () async {
    api.invokes['wy/central/downstream/m ▸ read_device_id'] = [
      Value.from({'vendor': 'acme', 'model': 'x1'}),
    ];

    await s.dispatchAndWait(
      InvokeNodeAction('wy/central/downstream/m', 'read_device_id'),
    );

    expect(
      s
          .state
          .nodes
          .results[InvokeNodeAction.resultId(
            'wy/central/downstream/m',
            'read_device_id',
          )]!
          .single,
      contains('"vendor": "acme"'),
    );
  });

  test('an answer success false is a user error with its message', () async {
    api.invokes['wy/central/sys/links ▸ install_zip'] = [
      Value.from({'success': false, 'message': 'no entry for this host'}),
    ];

    final st = await s.dispatchAndWait(
      InvokeNodeAction('wy/central/sys/links', 'install_zip'),
    );

    expect(
      (st.originalError! as UserException).reason,
      'no entry for this host',
    );
  });

  test('history rows become points, bools as 0/1', () async {
    api.histories['wy/central/downstream/m/fan'] = [
      const HistRow(1794108760000000, VBool(true), Quality.good),
      const HistRow(1794108761000000, VBool(false), Quality.bad),
    ];

    await s.dispatchAndWait(
      RetrieveHistoryAction('wy/central/downstream/m/fan'),
    );

    expect(s.state.nodes.history.map((h) => h.value), [1, 0]);
    expect(s.state.nodes.history.last.quality, 'bad');
    expect(s.state.nodes.historyKey, 'wy/central/downstream/m/fan');
  });
}
