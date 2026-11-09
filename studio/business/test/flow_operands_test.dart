import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_edge_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/set_operand_value_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/catalog_0221.dart';
import 'support/fake_wyrm.dart';

// Operand constants (ADR 0038 §7, spec 06 0.2.19), the `case` block and the
// new parameter ports (§5b, §8, spec 06 0.2.21) against the broker's own
// catalog.

final Map<String, NodeType> types = {
  for (final t in catalog0221())
    t['type']! as String: nodeTypeOf(Value.from(t)),
};

FlowBlock block(
  String id,
  String type, [
  Map<String, Object?> cfg = const {},
]) => FlowBlock(id: id, type: type, cfg: cfg.lock);

List<String> labels(List<FlowField> f) => [for (final x in f) x.label];

List<String> names(List<FlowField> f) => [for (final x in f) x.name];

FlowField field(FlowBlock b, String name, [List<FlowEdge> edges = const []]) =>
    fieldsOf(
      types[b.type],
      b,
      edges: edges,
    ).firstWhere((f) => f.name == name);

void main() {
  group('the catalog says which inputs take a constant', () {
    test('values: true is read', () {
      expect(types['concat']!.takesValues, isTrue);
      expect(types['case']!.takesValues, isTrue);
      expect(types['number']!.takesValues, isFalse);
      expect(types['stopwatch']!.takesValues, isFalse);
      expect(types['scale']!.takesValues, isFalse);
    });

    test('operands: in and the variable inputs, never a parameter port', () {
      expect(operandPortsOf(types['concat'], block('c', 'concat')), [
        'in.0',
        'in.1',
      ]);
      expect(operandPortsOf(types['if'], block('i', 'if')), ['in.0', 'in.1']);
      expect(operandPortsOf(types['round'], block('r', 'round')), ['in']);
      expect(operandPortsOf(types['case'], block('k', 'case')), [
        'in',
        'in.0',
        'in.1',
      ]);
      expect(
        operandPortsOf(types['stopwatch'], block('s', 'stopwatch')),
        isEmpty,
        reason: 'reset is an event',
      );
      expect(
        operandPortsOf(types['number'], block('n', 'number')),
        isEmpty,
        reason: "a variable's value is its constant",
      );
    });

    test('an operand field is marked; a parameter port is not', () {
      final c = block('c', 'concat');
      expect(field(c, 'in.0').operand, isTrue);
      expect(field(c, 'strict').operand, isFalse);
      final i = block('i', 'if');
      expect(field(i, 'in.0').operand, isTrue);
      expect(field(i, 'op').operand, isFalse);
      expect(field(i, 'then').operand, isFalse);
    });
  });

  group('values in the def mapper', () {
    test('typed: written under the engine port, read back', () {
      final t = types['concat'];
      final c = block('c', 'concat');
      final cfg = cfgWithOperandValue(t, c, 'in.0', 'AHU-')!;
      expect(cfg['values'], {'in.0': 'AHU-'});
      final c2 = c.copyWith(cfg: cfg);
      expect(operandValueOf(c2, 'in.0'), 'AHU-');
      final cfg2 = cfgWithOperandValue(t, c2, 'in.1', 2)!;
      expect(cfg2['values'], {'in.0': 'AHU-', 'in.1': 2});
      expect(
        cfgWithOperandValue(t, c2, 'in.0', '')!.containsKey('values'),
        isFalse,
        reason: 'the last constant gone: no values key',
      );
    });

    test('refused for parameter ports, events and variables', () {
      expect(
        cfgWithOperandValue(types['if'], block('i', 'if'), 'in.op', '>'),
        isNull,
      );
      expect(
        cfgWithOperandValue(
          types['round'],
          block('r', 'round'),
          'in.precision',
          2,
        ),
        isNull,
      );
      expect(
        cfgWithOperandValue(
          types['stopwatch'],
          block('s', 'stopwatch'),
          'reset',
          1,
        ),
        isNull,
      );
      expect(
        cfgWithOperandValue(types['number'], block('n', 'number'), 'in', 1),
        isNull,
      );
      expect(
        cfgWithOperandValue(types['concat'], block('c', 'concat'), 'in.9', 1),
        isNull,
        reason: 'no such variable input',
      );
    });

    test('configs compare by content: a values map is no identity', () {
      final a = {
        'values': {'in.0': 'AHU-'},
      }.lock;
      final b = {
        'values': {'in.0': 'AHU-'},
      }.lock;
      expect(sameCfg(a, b), isTrue);
      expect(
        sameCfg(
          a,
          {
            'values': {'in.0': 'AHU'},
          }.lock,
        ),
        isFalse,
      );
    });

    test('a ~def round trip keeps values', () {
      final def = Value.from({
        'id': 'f',
        'version': 3,
        'nodes': {
          'c': {
            'type': 'concat',
            'values': {'in.0': 'AHU-', 'in.1': 2},
          },
        },
        'edges': <Object>[],
      });
      final d = flowDraftOf('f', def);
      expect(operandValuesOf(d.blocks['c']!), {'in.0': 'AHU-', 'in.1': 2});
      final back = toDart(defOf(d, 4))! as Map;
      expect((back['nodes'] as Map)['c'], {
        'type': 'concat',
        'values': {'in.0': 'AHU-', 'in.1': 2},
      });
    });

    test('a field shows its typed value, a bound one what comes in', () {
      final c = block('c', 'concat', {
        'values': {'in.0': 'AHU-', 'in.1': 2},
      });
      const wire = FlowEdge(
        from: 'n',
        fromPort: 'out',
        to: 'c',
        toPort: 'in.1',
      );
      final unbound = FlowDraft(id: 'f', blocks: {'c': c}.lock);
      final bound = unbound.copyWith(edges: const [wire].lock);
      LiveValue? live(String k) => k == 'in:c.in.1'
          ? LiveValue(time: DateTime.utc(2026), value: 7)
          : null;

      final typed = fieldValue(c, field(c, 'in.1'), unbound, live);
      expect((typed.text, typed.bound, typed.live), ('2', false, false));
      final typedText = fieldValue(c, field(c, 'in.0'), unbound, live);
      expect(typedText.text, 'AHU-');

      final over = fieldValue(c, field(c, 'in.1', [wire]), bound, live);
      expect((over.text, over.bound, over.live), ('7', true, true));
    });
  });

  group('case, if, round, scale from the 0.2.21 catalog', () {
    test('case reads Input · Operation · Case 1 · Then 1 · Else · Output', () {
      final k = block('k', 'case');
      final rows = rowsOf(types['case'], k);
      expect(labels(rows), [
        'Input',
        'Operation',
        'Case 1',
        'Then 1',
        'Else',
        'Output',
      ]);
      expect(names(rows), ['in', 'op', 'in.0', 'in.1', 'else', 'out']);
      final v = variadicOf(types['case'], k)!;
      expect((v.step, v.min), (2, 2));
      expect(v.adds, ['2', '3']);
      expect(v.removes, isEmpty, reason: 'one pair at least');
      final more = block('k', 'case', {
        'inputs': ['0', '1', '2', '3'],
      });
      expect(labels(rowsOf(types['case'], more)), [
        'Input',
        'Operation',
        'Case 1',
        'Then 1',
        'Case 2',
        'Then 2',
        'Else',
        'Output',
      ]);
      expect(variadicOf(types['case'], more)!.removes, ['2', '3']);
    });

    test('case op and if op have the new operators', () {
      final caseOp = types['case']!.params.firstWhere((p) => p.name == 'op');
      expect(caseOp.choices, containsAll(['!=', 'contains', 'ends_with']));
      expect(caseOp.port, 'in.op');
      final ifOp = types['if']!.params.firstWhere((p) => p.name == 'op');
      expect(ifOp.choices, containsAll(['!=', 'contains', 'starts_with']));
    });

    test('round: Min precision bindable, a Text output', () {
      final rows = rowsOf(types['round'], block('r', 'round'));
      expect(labels(rows), [
        'Input',
        'Precision',
        'Min precision',
        'Output',
        'Text',
      ]);
      final min = rows.firstWhere((f) => f.name == 'min_precision');
      expect((min.inPort, min.outPort), ('in.min_precision', 'min_precision'));
    });

    test('scale k and b are bindable now', () {
      final k = field(block('s', 'scale'), 'k');
      expect((k.inPort, k.outPort), ('in.k', 'k'));
      final d = FlowDraft(
        id: 'f',
        blocks: {
          'n': block('n', 'number'),
          's': block('s', 'scale'),
        }.lock,
      );
      expect(
        bindRefusal(
          types,
          d,
          fromBlock: 'n',
          fromPort: 'out',
          toBlock: 's',
          to: k,
        ),
        isNull,
      );
    });
  });

  group('the editor writes values', () {
    late FakeWyrmApi api;
    late Store<AppState> s;
    final def = Value.from({
      'id': 'tags',
      'version': 1,
      'nodes': {
        'n': {'type': 'number', 'value': 5},
        'c': {
          'type': 'concat',
          'values': {'in.0': 'AHU-'},
        },
        'k': {'type': 'case'},
        'w': {'type': 'stopwatch'},
      },
      'edges': <Object>[],
    });

    setUp(() async {
      final login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());
      api
        ..invokes['wy/central/dataflows ▸ node_types'] = [
          Value.from(catalog0221()),
        ]
        ..invokes['wy/central/dataflows/tags ▸ history'] = [
          Value.from([toDart(def)]),
        ];
      await s.dispatchAndWait(LoadFlowAction('tags'));
    });

    FlowBlock b(String id) => s.state.flowEditor.draft!.blocks[id]!;

    test('typing a value stores it under the engine port', () {
      s.dispatchSync(SetOperandValueAction('c', 'in.1', 2));
      expect(operandValuesOf(b('c')), {'in.0': 'AHU-', 'in.1': 2});
      expect(s.state.flowEditor.dirty, isTrue);
      s.dispatchSync(SetOperandValueAction('c', 'in.0', null));
      expect(operandValuesOf(b('c')), {'in.1': 2});
    });

    test('refused for a parameter port and for a type without values', () {
      final before = s.state.flowEditor.draft;
      s
        ..dispatchSync(SetOperandValueAction('c', 'in.strict', true))
        ..dispatchSync(SetOperandValueAction('k', 'in.op', '>'))
        ..dispatchSync(SetOperandValueAction('w', 'reset', 1))
        ..dispatchSync(SetOperandValueAction('n', 'in', 3));
      expect(s.state.flowEditor.draft, before);
    });

    test('binding keeps the value; unbinding brings it back', () {
      s.dispatchSync(ConnectPortsAction('n', 'out', 'c', 'in.0'));
      expect(operandValueOf(b('c'), 'in.0'), 'AHU-', reason: 'kept in cfg');
      final d = s.state.flowEditor.draft!;
      final f = field(b('c'), 'in.0', d.edges.toList());
      expect(fieldValue(b('c'), f, d, (_) => null).bound, isTrue);
      // The editor unbinds an operand without a parameter to keep into.
      s.dispatchSync(DisconnectEdgeAction('c', 'in.0', param: f.spec?.name));
      final after = s.state.flowEditor.draft!;
      expect(after.edges, isEmpty);
      final shown = fieldValue(
        b('c'),
        field(b('c'), 'in.0'),
        after,
        (_) => null,
      );
      expect((shown.text, shown.bound), ('AHU-', false));
    });

    test('moving the wire off an operand leaves its value', () {
      s
        ..dispatchSync(ConnectPortsAction('n', 'out', 'c', 'in.0'))
        ..dispatchSync(RebindEdgeAction('c', 'in.0', 'c', 'in.1'));
      expect(operandValueOf(b('c'), 'in.0'), 'AHU-');
      expect(s.state.flowEditor.draft!.edges.single.toPort, 'in.1');
    });

    test('case grows and shrinks by a pair; a removed pair takes its '
        'constants and wires', () {
      s.dispatchSync(ResizeInputsAction('k', add: true));
      expect(b('k').cfg['inputs'], ['0', '1', '2', '3']);
      s
        ..dispatchSync(SetOperandValueAction('k', 'in.2', 10))
        ..dispatchSync(SetOperandValueAction('k', 'in.3', 'normal'))
        ..dispatchSync(SetOperandValueAction('k', 'in.0', 90))
        ..dispatchSync(ConnectPortsAction('n', 'out', 'k', 'in.3'))
        ..dispatchSync(ResizeInputsAction('k', add: false));
      expect(b('k').cfg['inputs'], ['0', '1']);
      expect(operandValuesOf(b('k')), {'in.0': 90});
      expect(s.state.flowEditor.draft!.edges, isEmpty);
      s.dispatchSync(ResizeInputsAction('k', add: false));
      expect(b('k').cfg['inputs'], ['0', '1'], reason: 'one pair at least');
    });
  });
}
