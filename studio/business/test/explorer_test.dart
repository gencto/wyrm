import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_history_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/stage_invoke_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/wyrm/calls.dart';
import 'package:business/wyrm/failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/error_kind.dart';
import 'package:models/param_spec.dart';
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

  test(
    'selecting downstream or the site root reads no meta, shows a folder',
    () async {
      // Nobody answers a full ~meta on these two (the links answer for
      // themselves below them): the root times out, downstream answers
      // disconnected.
      api.errors['wy/central/downstream'] = WyrmException.of(
        Status.disconnected,
        'wy/central/downstream/~meta is not connected',
      );

      for (final key in ['wy/central/downstream', 'wy/central']) {
        final st = await s.dispatchAndWait(SelectNodeAction(key));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(st.originalError, isNull);
        expect(s.state.nodes.selectedNode, key);
        expect(s.state.nodes.detail[key]?.profile, 'wy:folder');
        expect(s.state.nodes.detail[key]?.actions, isEmpty);
        expect(
          api.calls.where((c) => c.op == 'list').map((c) => c.key),
          contains(key),
        );
      }
      expect(api.calls.where((c) => c.op == 'meta'), isEmpty);
    },
  );

  test('a meta refused on another key is still a user error', () async {
    const key = 'wy/central/downstream/modbus';
    api.errors[key] = WyrmException.of(Status.disconnected, 'gone');

    final st = await s.dispatchAndWait(RetrieveNodeDetailAction(key));

    // The status stays data: it is not flattened into the text.
    final e = (st.originalError! as StudioException).error;
    expect(e.status, StatusCode.of(Status.disconnected));
    expect(e.kind, ErrorKind.reach);
    expect(e.message, 'gone');
    expect(e.where, '$key › meta');
    expect(s.state.nodes.detail[key], isNull);
  });

  test('a listed enum point gets its names from its full meta', () async {
    // A list carries no enum names (spec 02 key 3): the meta does.
    const dev = 'wy/central/downstream/modbus/line1';
    api.metas['$dev/status'] = NodeMeta(
      ty: TypeCode.enum_,
      enumValues: ['Unknown', 'Connecting', 'Connected', 'Failed'],
    );
    api.errors['$dev/mode'] = WyrmException.of(Status.notFound, 'gone');

    s.dispatchSync(ToggleNodeAction(dev, open: true));
    api.lists[dev]!.add(
      ListRefreshed([
        Child('status', NodeMeta(ty: TypeCode.enum_)),
        Child('mode', NodeMeta(ty: TypeCode.enum_)),
        Child('requests', NodeMeta(ty: TypeCode.number)),
      ]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      api.calls.where((c) => c.op == 'meta').map((c) => c.key),
      unorderedEquals(['$dev/status', '$dev/mode']),
    );
    expect(s.state.nodes.detail['$dev/status']!.choices.unlock, [
      'Unknown',
      'Connecting',
      'Connected',
      'Failed',
    ]);
    // A meta that fails is no dialog: the point shows its number.
    expect(s.state.nodes.detail['$dev/mode'], isNull);

    // A changed child (its quality) is not read again.
    api.lists[dev]!.add(
      ChildChanged(Child('status', NodeMeta(ty: TypeCode.enum_, q: 1))),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      api.calls.where((c) => c.op == 'meta' && c.key == '$dev/status'),
      hasLength(1),
    );
  });

  test('a staged enum value shows its name', () async {
    const key = 'wy/central/downstream/modbus/line1/mode';
    api.metas[key] = NodeMeta(
      ty: TypeCode.enum_,
      enumValues: ['auto', 'manual'],
      writable: Writable.write,
    );
    await s.dispatchAndWait(RetrieveNodeDetailAction(key));

    s.dispatchSync(StageValueAction(key, 1, from: 'auto'));

    final c = s.state.changes.table.values.single;
    expect((c.value, c.from, c.to), (1, 'auto', 'manual'));
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
      final set = api.calls.lastWhere((c) => c.op != 'meta');
      expect(set.op, 'set');
      expect(set.value, const VFloat(21.5));
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

  group('a node is renamed by edit with display (ADR 0042 §4)', () {
    const dev = 'wy/central/downstream/m/dev';

    test('a new name alone is sent as the rename', () async {
      s.dispatchSync(
        StageInvokeAction(dev, 'edit', {'display': 'Boiler room'}),
      );
      final c = s.state.changes.table.values.single;
      expect(c.op, 'Edit');
      expect(c.args.unlock, {'display': 'Boiler room'});
      expect(c.to, 'display: Boiler room');

      await s.dispatchAndWait(ApplyChangesAction());
      final sent = api.calls.lastWhere((x) => x.op == 'invoke');
      expect(sent.key, dev);
      expect(sent.action, 'edit');
      expect(sent.args, Value.from({'display': 'Boiler room'}));
    });

    test('a cleared name is sent as "", other empty fields are not', () {
      // `edit` prefilled the name: clearing it clears it.
      final keep = clearedNames(const [
        ParamSpec(name: 'display', defaultValue: 'Boiler room'),
        ParamSpec(name: 'host', defaultValue: '10.0.0.5'),
      ]);
      expect(keep, {'display'});
      s.dispatchSync(
        StageInvokeAction(dev, 'edit', {
          'display': '',
          'host': '',
          'port': 502,
        }, keepEmpty: keep),
      );
      final c = s.state.changes.table.values.single;
      expect(c.args.unlock, {'display': '', 'port': 502});
      expect(c.to, 'display: "", port: 502');
    });

    test('an empty name that was never there stays out (an Add form, an '
        'app that does not prefill it)', () {
      expect(clearedNames(const [ParamSpec(name: 'display')]), isEmpty);
      expect(
        clearedNames(const [ParamSpec(name: 'display', defaultValue: ' ')]),
        isEmpty,
      );
      s.dispatchSync(
        StageInvokeAction(dev, 'add_class', {'id': 'c1', 'display': ''}),
      );
      expect(s.state.changes.table.values.single.args.unlock, {'id': 'c1'});
    });
  });

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
