import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/changes/actions/apply_changes_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/nodes/actions/add_nodes_action.dart';
import 'package:business/redux/nodes/actions/check_points_action.dart';
import 'package:business/redux/nodes/actions/clear_selection_action.dart';
import 'package:business/redux/nodes/actions/mark_nodes_action.dart';
import 'package:business/redux/nodes/actions/retrieve_audit_action.dart';
import 'package:business/redux/nodes/actions/retrieve_details_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/nodes/actions/select_point_action.dart';
import 'package:business/redux/nodes/actions/set_children_action.dart';
import 'package:business/redux/nodes/actions/stage_point_edit_action.dart';
import 'package:business/redux/nodes/actions/stage_value_action.dart';
import 'package:business/wyrm/keys.dart';
import 'package:business/wyrm/points.dart';
import 'package:business/wyrm/session.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const dev = 'wy/central/downstream/modbus/line1/ahu1';

/// A modbus point's meta: its `cfg` and an `edit` whose defaults are it.
NodeMeta pointMeta({num poll = 1.0, String unit = '°C'}) => NodeMeta(
  ty: TypeCode.number,
  cfg: {
    'table': const VStr('holding'),
    'addr': const VInt(10),
    'dtype': const VStr('f32'),
    'poll_s': VFloat(poll.toDouble()),
    'unit': VStr(unit),
  },
  actions: {
    'edit': ActionMeta()
      ..level = Perm.config
      ..params['table'] = ParamMeta(defaultValue: const VStr('holding'))
      ..params['addr'] = ParamMeta(defaultValue: const VInt(10))
      ..params['poll_s'] = ParamMeta(defaultValue: VFloat(poll.toDouble()))
      ..params['unit'] = ParamMeta(defaultValue: VStr(unit)),
  },
);

void main() {
  late FakeLogin login;
  late FakeWyrmApi api;
  late Store<AppState> s;

  Future<void> logIn({List<(String, String)> grants = const []}) async {
    login = FakeLogin(
      session: FakeSession(
        who: WhoAmI(
          subject: 'user:olena',
          site: 'central',
          roles: const ['operator'],
          // as the gateway sends it: the highest level of the grants
          max: grants.isEmpty
              ? 'write'
              : grants.map((g) => g.$2).reduce(
                  (a, b) => levelRank(a) >= levelRank(b) ? a : b,
                ),
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
  }

  NodeInfo point(String name) => NodeInfo(
    key: '$dev/$name',
    name: name,
    type: 'number',
  );

  test('diagnostic values are not points', () {
    expect(isPoint(point('temp')), isTrue);
    expect(isPoint(point('requests')), isFalse);
    expect(isPoint(point('last_rtt_ms')), isFalse);
    expect(isPoint(const NodeInfo(key: 'k', name: 'status')), isFalse);
    expect(pollText(0.5), '500 ms');
    expect(pollText(1.0), '1 s');
    expect(pollText(2.5), '2.5 s');
  });

  group('selection', () {
    setUp(logIn);

    test('a point row shows in the inspector; the device stays', () async {
      s.dispatchSync(SelectNodeAction(dev));
      api.metas['$dev/temp'] = pointMeta();
      s.dispatchSync(SelectPointAction('$dev/temp'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(s.state.nodes.selectedNode, dev);
      expect(s.state.nodes.point, '$dev/temp');
      expect(s.state.nodes.detail['$dev/temp']?.cfg['poll_s'], '1');
    });

    test('selecting a point key shows its parent with the point', () {
      s
        ..dispatchSync(SetChildrenAction(dev, [point('temp')].lock))
        ..dispatchSync(SelectNodeAction('$dev/temp'));

      expect(s.state.nodes.selectedNode, dev);
      expect(s.state.nodes.point, '$dev/temp');
    });

    test('the device children get their meta read, diagnostics not', () async {
      s.dispatchSync(SelectNodeAction(dev));
      api.metas['$dev/temp'] = pointMeta();
      s.dispatchSync(
        SetChildrenAction(
          dev,
          [point('temp'), point('requests'), point('gone')].lock,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final metas = api.calls.where((c) => c.op == 'meta').map((c) => c.key);
      expect(metas, containsAll(['$dev/temp', '$dev/gone']));
      expect(metas, isNot(contains('$dev/requests')));
      expect(s.state.nodes.detail.containsKey('$dev/temp'), isTrue);
      expect(
        s.state.nodes.detail.containsKey('$dev/gone'),
        isFalse,
        reason: 'a point that does not answer keeps its dashes, no dialog',
      );
    });

    test('toggle, range and all check rows; Esc clears', () {
      final order = ['$dev/a', '$dev/b', '$dev/c', '$dev/d'];
      s
        ..dispatchSync(CheckPointsAction.toggle('$dev/b'))
        ..dispatchSync(CheckPointsAction.range('$dev/d', order));
      expect(s.state.nodes.checked, {'$dev/b', '$dev/c', '$dev/d'});

      s.dispatchSync(CheckPointsAction.toggle('$dev/c'));
      expect(s.state.nodes.checked, {'$dev/b', '$dev/d'});

      s.dispatchSync(CheckPointsAction.all(order));
      expect(s.state.nodes.checked, order.toSet());
      s.dispatchSync(CheckPointsAction.all(order));
      expect(s.state.nodes.checked, isEmpty);

      s
        ..dispatchSync(CheckPointsAction.toggle('$dev/a'))
        ..dispatchSync(MarkNodesAction.toggle(dev))
        ..dispatchSync(ClearSelectionAction());
      expect(s.state.nodes.checked, isEmpty);
      expect(s.state.nodes.marked, isEmpty);
      expect(s.state.nodes.point, isNull);
    });

    test('Shift-click in the tree marks from the selected node', () {
      const order = ['wy/central/downstream', 'a', 'b', 'c'];
      s
        ..dispatchSync(SelectNodeAction('wy/central/downstream'))
        ..dispatchSync(MarkNodesAction.range('b', order));
      expect(s.state.nodes.marked, {'wy/central/downstream', 'a', 'b'});
    });
  });

  group('staged point edits', () {
    setUp(() async {
      await logIn(grants: const [('wy/central/**', 'config')]);
      api.metas['$dev/temp'] = pointMeta();
      await s.dispatchAndWait(RetrieveDetailsAction(['$dev/temp']));
    });

    test('edits of one point merge into one edit with typed args', () {
      s
        ..dispatchSync(StagePointEditAction('$dev/temp', 'poll_s', 0.5))
        ..dispatchSync(StagePointEditAction('$dev/temp', 'unit', 'K'));

      expect(s.state.changes.view, ['edit:$dev/temp']);
      final c = s.state.changes.table['edit:$dev/temp']!;
      expect((c.field, c.from, c.to), ('poll, unit', '1 s, °C', '500 ms, K'));
      expect((c.action, c.level), ('edit', 'config'));
      expect(c.args.unlock, {
        'table': 'holding',
        'addr': 10,
        'poll_s': 0.5,
        'unit': 'K',
      });
    });

    test('back to the current value unstages it', () {
      s
        ..dispatchSync(StagePointEditAction('$dev/temp', 'poll_s', 0.5))
        ..dispatchSync(StagePointEditAction('$dev/temp', 'poll_s', 1));
      expect(s.state.changes.view, isEmpty);
    });

    test('apply sends the edit and reads the point again', () async {
      s.dispatchSync(StagePointEditAction('$dev/temp', 'poll_s', 0.5));
      api.invokes['$dev/temp ▸ edit'] = [];
      api.metas['$dev/temp'] = pointMeta(poll: 0.5);

      await s.dispatchAndWait(ApplyChangesAction());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final edit = api.calls.singleWhere((c) => c.op == 'invoke');
      expect(edit.args?['poll_s'], const VFloat(0.5));
      expect(edit.args?['addr'], const VInt(10));
      expect(s.state.changes.view, isEmpty);
      expect(s.state.nodes.detail['$dev/temp']?.cfg['poll_s'], '0.5');
    });
  });

  test('apply leaves the changes the user lacks the level for', () async {
    await logIn(grants: const [('wy/central/downstream/**', 'write')]);
    api.metas['$dev/temp'] = pointMeta();
    await s.dispatchAndWait(RetrieveDetailsAction(['$dev/temp']));
    s
      ..dispatchSync(StagePointEditAction('$dev/temp', 'poll_s', 0.5))
      ..dispatchSync(StageValueAction('$dev/sp', 21, from: '20'));

    await s.dispatchAndWait(ApplyChangesAction());

    expect(api.calls.where((c) => c.op == 'invoke'), isEmpty);
    expect(api.calls.where((c) => c.op == 'set').single.key, '$dev/sp');
    expect(s.state.changes.view, ['edit:$dev/temp']);
  });

  group('point metas', () {
    setUp(logIn);

    test('20 points never have more than 8 meta calls in flight', () async {
      api.metaDelay = const Duration(milliseconds: 5);
      final points = [for (var i = 0; i < 20; i++) point('p$i')];
      for (final p in points) {
        api.metas[p.key] = pointMeta();
      }
      // The first list, and points arriving one by one at the same time.
      s
        ..dispatchSync(SelectNodeAction(dev))
        ..dispatchSync(SetChildrenAction(dev, points.take(12).toList().lock));
      for (final p in points.skip(12)) {
        s.dispatchSync(AddNodesAction([p].lock));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(api.metaMaxInFlight, RetrieveDetailsAction.maxInFlight);
      final asked = api.calls
          .where((c) => c.op == 'meta' && c.key.startsWith('$dev/'))
          .map((c) => c.key);
      expect(asked.toSet(), {for (final p in points) p.key});
      expect(asked, hasLength(20), reason: 'each point read once');
      for (final p in points) {
        expect(s.state.nodes.detail.containsKey(p.key), isTrue);
      }
    });

    test('a point added later gets its meta; a read one is cached', () async {
      s.dispatchSync(SelectNodeAction(dev));
      api.metas['$dev/late'] = pointMeta();
      s.dispatchSync(AddNodesAction([point('late')].lock));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(s.state.nodes.detail.containsKey('$dev/late'), isTrue);

      s.dispatchSync(AddNodesAction([point('late')].lock));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        api.calls.where((c) => c.op == 'meta' && c.key == '$dev/late'),
        hasLength(1),
      );
    });
  });

  test('audit keeps the records of the node and below, newest first', () async {
    await logIn();
    api.invokes['wy/central/sys/audit ▸ tail'] = [
      Value.from([
        {
          'key': '$dev/sp/~set',
          'op': 'set',
          'sub': 'user:a',
          't': 1,
          'status': 0,
        },
        {'key': 'wy/central/downstream/other/~set', 'op': 'set', 't': 2},
        {'key': '$dev/~act/edit', 'op': 'invoke', 'sub': 'user:b', 't': 3},
      ]),
    ];

    await s.dispatchAndWait(RetrieveAuditAction(dev));

    expect(s.state.nodes.audit.map((e) => (e.op, e.who)), [
      ('invoke', 'user:b'),
      ('set', 'user:a'),
    ]);
  });
}
