import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/watch_flow_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/services/flow_watch/flow_watch.dart';
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
import 'package:models/quality.dart' as m;
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

// The catalog as `dataflows` ▸ `node_types` answers today
// (crates/wyrm-flow/src/catalog.rs), trimmed to what the tests read.
final List<Map<String, Object>> today = [
  {
    'type': 'scale',
    'category': 'Math',
    'inputs': [
      'in',
      'in.input_min',
      'in.input_max',
      'in.output_min',
      'in.output_max',
    ],
    'outputs': ['out', 'input_out_of_range'],
    'params': [
      {'name': 'k', 'type': 'number'},
      {'name': 'b', 'type': 'number'},
      {'name': 'input_min', 'type': 'number'},
      {'name': 'input_max', 'type': 'number'},
      {'name': 'output_min', 'type': 'number'},
      {'name': 'output_max', 'type': 'number'},
    ],
  },
  {
    'type': 'modulo',
    'category': 'Math',
    'inputs': ['in', 'in.modulo'],
    'outputs': ['quotient', 'remainder'],
    'params': [
      {'name': 'modulo', 'type': 'number'},
    ],
  },
  {
    'type': 'latch',
    'category': 'Logic',
    'inputs': ['in', 'reset'],
    'outputs': ['out'],
    'params': [
      {
        'name': 'reset',
        'type': 'string',
        'choices': ['manual', 'auto'],
        'default': 'manual',
      },
    ],
  },
  {
    'type': 'if',
    'category': 'Logic',
    'inputs': ['in.then', 'in.else'],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      {
        'name': 'op',
        'type': 'string',
        'choices': ['=', 'and', 'or', '>', '<', '>=', '<='],
        'default': '=',
      },
      {'name': 'then', 'type': 'dynamic'},
      {'name': 'else', 'type': 'dynamic'},
      {'name': 'inputs', 'type': 'array'},
    ],
  },
  {
    'type': 'add',
    'category': 'Math',
    'inputs': <String>[],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      {'name': 'inputs', 'type': 'array'},
    ],
  },
  {
    'type': 'subscribe',
    'category': 'Sources',
    'inputs': <String>[],
    'outputs': ['out'],
    'params': [
      {'name': 'key', 'type': 'string', 'required': true},
    ],
  },
  {
    'type': 'publish',
    'category': 'Outputs',
    'inputs': ['in'],
    'outputs': <String>[],
    'params': [
      {'name': 'node', 'type': 'string', 'required': true},
      {'name': 'meta', 'type': 'map'},
    ],
  },
  {
    'type': 'set',
    'category': 'Outputs',
    'inputs': ['in'],
    'outputs': <String>[],
    'params': [
      {'name': 'path', 'type': 'string', 'required': true},
      {
        'name': 'on',
        'type': 'string',
        'choices': ['change', 'any'],
        'default': 'change',
      },
    ],
  },
];

Map<String, NodeType> catalog(List<Map<String, Object>> raw) => {
  for (final t in raw) t['type']! as String: nodeTypeOf(Value.from(t)),
};

FlowBlock block(
  String id,
  String type, [
  Map<String, Object?> cfg = const {},
]) => FlowBlock(id: id, type: type, cfg: cfg.lock);

List<String> labels(List<FlowField> f) => [for (final x in f) x.label];

void main() {
  final types = catalog(today);

  group("fields from today's catalog", () {
    test(
      'scale: fields, not ports; unset optional parameters off the block',
      () {
        final b = block('scale1', 'scale');
        expect(labels(rowsOf(types['scale'], b)), [
          'in',
          'input_min',
          'input_max',
          'output_min',
          'output_max',
          'out',
          'input_out_of_range',
        ]);
        final all = fieldsOf(types['scale'], b);
        expect(labels(all), contains('k'), reason: 'the inspector lists it');
        final min = all.firstWhere((f) => f.label == 'input_min');
        expect(min.inPort, 'in.input_min');
        expect(min.outPort, 'input_min', reason: 'the echo output');
        expect(min.kind, FieldKind.param);
        final k = all.firstWhere((f) => f.label == 'k');
        expect(k.inPort, isNull, reason: 'no in.k: no left port');
        expect(k.outPort, 'k');
        final input = all.firstWhere((f) => f.label == 'in');
        expect((input.inPort, input.outPort), ('in', 'in'));
        final out = all.firstWhere((f) => f.label == 'out');
        expect((out.inPort, out.outPort), (null, 'out'));
      },
    );

    test('modulo reads in · modulo · quotient · remainder', () {
      expect(labels(rowsOf(types['modulo'], block('m', 'modulo'))), [
        'in',
        'modulo',
        'quotient',
        'remainder',
      ]);
    });

    test('latch: an input and a parameter both named reset echo neither', () {
      final f = fieldsOf(types['latch'], block('l', 'latch'));
      final param = f.firstWhere((x) => x.kind == FieldKind.param);
      final input = f.firstWhere((x) => x.inPort == 'reset');
      expect(param.outPort, isNull);
      expect(input.outPort, isNull);
      expect(param.inPort, isNull, reason: 'no in.reset');
    });

    test('if: op, then, else, the variable inputs by number, out', () {
      final b = block('if1', 'if', {'op': '>'});
      expect(labels(rowsOf(types['if'], b)), [
        'op',
        'then',
        'else',
        '0',
        '1',
        'out',
      ]);
      final zero = fieldsOf(types['if'], b).firstWhere((f) => f.label == '0');
      expect((zero.inPort, zero.outPort), ('in.0', 'in.0'));
      final v = variadicOf(types['if'], b)!;
      expect(v.names, ['0', '1']);
      expect((v.min, v.next), (2, '2'));
    });

    test('a tree point reads its name; publish and set take no echo', () {
      final sub = rowsOf(
        types['subscribe'],
        block('level', 'subscribe', {'key': 'downstream/modbus/tank/level'}),
      );
      expect(labels(sub), ['level']);
      expect((sub.single.inPort, sub.single.outPort), (null, 'out'));

      final pub = rowsOf(
        types['publish'],
        block('p', 'publish', {'node': 'x'}),
      );
      expect(labels(pub), ['node', 'value']);
      expect(pub.every((f) => f.outPort == null), isTrue);
      expect(pub.first.inPort, isNull, reason: 'the engine has no in.node');

      final set = rowsOf(
        types['set'],
        block('s', 'set', {'path': 'downstream/plc/fan', 'on': 'change'}),
      );
      expect(labels(set), ['fan'], reason: 'its config is in the inspector');
      expect((set.single.inPort, set.single.outPort), ('in', 'in'));
    });

    test('block height follows the rows and the − / + row', () {
      expect(
        blockHeight(types['modulo'], block('m', 'modulo')),
        32 + 6 + 4 * 28 + 8,
      );
      expect(
        blockHeight(types['add'], block('a', 'add')),
        32 + 6 + 3 * 28 + 8 + 38,
      );
    });
  });

  group('fields with ADR 0038 in the catalog', () {
    final adr = catalog([
      {
        'type': 'scale',
        'inputs': ['in', 'in.lo'],
        'outputs': ['out'],
        'echo_inputs': false,
        'port_types': {'in': 'number', 'out': 'number'},
        'params': [
          {'name': 'lo', 'type': 'number', 'port': 'in.lo', 'default': 0},
          {'name': 'k', 'type': 'number', 'default': 1, 'echo': false},
        ],
      },
    ]);

    test('port, echo, typed default and echo_inputs are read', () {
      final t = adr['scale']!;
      expect(t.echoInputs, isFalse);
      expect(t.portTypes['in'], 'number');
      final f = fieldsOf(t, block('s', 'scale'));
      final lo = f.firstWhere((x) => x.label == 'lo');
      final k = f.firstWhere((x) => x.label == 'k');
      final input = f.firstWhere((x) => x.label == 'in');
      expect((lo.inPort, lo.outPort), ('in.lo', 'lo'));
      expect(k.outPort, isNull, reason: 'echo: false');
      expect(k.onBlock, isTrue, reason: 'it has a default to show');
      expect(input.outPort, isNull, reason: 'echo_inputs: false');
      final v = fieldValue(
        block('s', 'scale'),
        k,
        const FlowDraft(id: 'x'),
        (_) => null,
      );
      expect(v.text, '1', reason: 'the typed default');
    });
  });

  group('values', () {
    final b = block('scale1', 'scale', {'input_max': 4095});
    final t = types['scale'];
    FlowField f(String l) => fieldsOf(t, b).firstWhere((x) => x.label == l);
    final live = <String, LiveValue>{
      portKey('in', 'scale1', 'in'): LiveValue(
        time: DateTime(2026),
        value: 3790,
        quality: m.Quality.bad,
      ),
      portKey('out', 'scale1', 'out'): LiveValue(
        time: DateTime(2026),
        value: 92.554,
      ),
      portKey('in', 'scale1', 'in.input_max'): LiveValue(
        time: DateTime(2026),
        value: 4000,
      ),
    };
    final unbound = FlowDraft(id: 'x', blocks: {'scale1': b}.lock);
    final bound = unbound.copyWith(
      edges: [
        const FlowEdge(
          from: 'c',
          fromPort: 'out',
          to: 'scale1',
          toPort: 'in.input_max',
        ),
      ].lock,
    );

    test('a typed parameter shows its value, an output its sample', () {
      expect(fieldValue(b, f('input_max'), unbound, live.get).text, '4095');
      expect(fieldValue(b, f('input_min'), unbound, live.get).text, '');
      expect(fieldValue(b, f('out'), unbound, live.get).text, '92.554');
      final input = fieldValue(b, f('in'), unbound, live.get);
      expect((input.text, input.bad), ('3790', true));
    });

    test('a binding wins over the typed value', () {
      final v = fieldValue(b, f('input_max'), bound, live.get);
      expect((v.text, v.bound), ('4000', true));
      final none = fieldValue(b, f('input_max'), bound, (_) => null);
      expect((none.text, none.bound), ('4095', true));
    });
  });

  group('binding in the definition', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    final def = Value.from({
      'id': 'tank',
      'version': 2,
      'nodes': {
        'c': {'type': 'scale', 'input_max': 100},
        'sum': {'type': 'add'},
        'gate': {'type': 'scale', 'input_max': 10},
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
        ..invokes['wy/central/dataflows ▸ node_types'] = [Value.from(today)]
        ..invokes['wy/central/dataflows/tank ▸ history'] = [
          Value.from([toDart(def)]),
        ]
        ..invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': true}),
        ];
      await s.dispatchAndWait(LoadFlowAction('tank'));
    });

    List<List<String>> edges() => [
      for (final e
          in (toDart(defOf(s.state.flowEditor.draft!, 3))! as Map)['edges']
              as List)
        [for (final x in e as List) x as String],
    ];

    test('a parameter feeds another field through its echo output', () {
      s.dispatchSync(ConnectPortsAction('c', 'input_max', 'sum', 'in.0'));
      expect(edges(), [
        ['c.input_max', 'sum.in.0'],
      ]);
      expect(s.state.flowEditor.dirty, isTrue);
    });

    test('unbinding keeps the last value as the typed value', () {
      s
        ..dispatchSync(ConnectPortsAction('c', 'out', 'gate', 'in.input_max'))
        ..dispatchSync(
          DisconnectEdgeAction(
            'gate',
            'in.input_max',
            param: 'input_max',
            keep: 42,
          ),
        );
      expect(edges(), isEmpty);
      expect(s.state.flowEditor.draft!.blocks['gate']!.cfg['input_max'], 42);
    });

    test('− and + change the inputs and drop the wires of the one removed', () {
      s
        ..dispatchSync(ResizeInputsAction('sum', add: true))
        ..dispatchSync(ConnectPortsAction('c', 'out', 'sum', 'in.2'))
        ..dispatchSync(ConnectPortsAction('sum', 'in.2', 'gate', 'in'));
      expect(s.state.flowEditor.draft!.blocks['sum']!.cfg['inputs'], [
        '0',
        '1',
        '2',
      ]);
      expect(edges(), hasLength(2));

      s.dispatchSync(ResizeInputsAction('sum', add: false));
      expect(s.state.flowEditor.draft!.blocks['sum']!.cfg['inputs'], [
        '0',
        '1',
      ]);
      expect(edges(), isEmpty, reason: 'into in.2 and out of its echo');

      s.dispatchSync(ResizeInputsAction('sum', add: false));
      expect(
        s.state.flowEditor.draft!.blocks['sum']!.cfg['inputs'],
        ['0', '1'],
        reason: "not below the type's two",
      );
    });

    test('a loaded flow equals its deployed version until edited', () async {
      final ed = s.state.flowEditor;
      expect(defOf(ed.draft!, 0), defOf(ed.deployed!, 0));
      s.dispatchSync(ResizeInputsAction('sum', add: true));
      final now = s.state.flowEditor;
      expect(defOf(now.draft!, 0) == defOf(now.deployed!, 0), isFalse);

      // Reopening the same flow keeps the draft.
      await s.dispatchAndWait(LoadFlowAction('tank'));
      expect(
        s.state.flowEditor.draft!.blocks['sum']!.cfg['inputs'],
        ['0', '1', '2'],
      );
    });

    test("the editor follows the flow's watch while it is open", () async {
      api.streamed.add('wy/central/dataflows/tank ▸ watch');
      s.dispatchSync(WatchFlowAction('tank'));
      await Future<void>.delayed(Duration.zero);
      expect(
        api.calls.where((c) => c.action == 'watch').single.args,
        Value.from({'max_hz': 4}),
      );
      s.dispatchSync(WatchFlowAction(null));
    });
  });

  group('the watch service', () {
    late FakeWyrmApi api;
    late _Listener heard;
    late FlowWatchService svc;
    const id = 'wy/central/dataflows/tank ▸ watch';

    setUp(() {
      api = FakeWyrmApi()..streamed.add(id);
      heard = _Listener();
      svc = FlowWatchService(
        listener: heard,
        flushEvery: const Duration(milliseconds: 1),
        retryFirst: const Duration(milliseconds: 5),
        retryMax: const Duration(milliseconds: 20),
      )..attach(api);
    });

    tearDown(() => svc.dispose());

    Future<void> settle([int ms = 20]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('a snapshot, then a change, batched', () async {
      svc.follow('wy/central/dataflows/tank');
      await settle();
      heard.batches.clear();
      api.opened[id]!.single
        ..add(
          Value.from({
            't': 1700000000000000,
            'snapshot': true,
            'nodes': {
              'scale1': {
                'in': {
                  'in': [3790, 0],
                },
                'out': {
                  'out': [92.6, 'good'],
                },
                'params': {'input_max': 4095},
              },
            },
          }),
        )
        ..add(
          Value.from({
            't': 1700000000100000,
            'snapshot': false,
            'nodes': {
              'scale1': {
                'in': {
                  'in': [3800, 2],
                },
              },
            },
          }),
        );
      await settle();
      expect(heard.batches, hasLength(1), reason: 'one flush for both rows');
      final (changed, reset) = heard.batches.single;
      expect(reset, isTrue);
      expect(changed['in:scale1.in']!.value, 3800);
      expect(changed['in:scale1.in']!.quality, m.Quality.bad);
      expect(changed['out:scale1.out']!.value, 92.6);
      expect(changed['param:scale1.input_max']!.value, 4095);
    });

    test('an end opens it again; a heartbeat changes nothing', () async {
      svc.follow('wy/central/dataflows/tank');
      await settle(2);
      final first = api.opened[id]!.single
        ..add(Value.from({'t': 1, 'nodes': <String, Object>{}}));
      await first.close();
      await settle(30);
      expect(api.opened[id], hasLength(2));
      expect(heard.batches.where((b) => b.$1.isNotEmpty), isEmpty);
    });

    test('a redeploy drops the values and opens it again', () async {
      svc.follow('wy/central/dataflows/tank');
      await settle(2);
      heard.batches.clear();
      final first = api.opened[id]!.single
        ..add(Value.from({'t': 1, 'redeployed': 3}));
      await first.close();
      await settle(30);
      expect(heard.batches.any((b) => b.$2), isTrue);
      expect(heard.redeployed, [3]);
      expect(api.opened[id], hasLength(2));
    });

    test('a broker without the action is not asked again, quietly', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(
        Status.notSupported,
        'wy/central/dataflows/tank/~act/watch',
      );
      svc.follow('wy/central/dataflows/tank');
      await settle(40);
      expect(api.calls.where((c) => c.action == 'watch'), hasLength(1));
      expect(svc.refused, isTrue);
      expect(heard.refused, [Status.notSupported]);
    });

    test('a refusal of rights is told, and not asked again', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(Status.permissionDenied, '');
      svc.follow('wy/central/dataflows/tank');
      await settle(40);
      expect(api.calls.where((c) => c.action == 'watch'), hasLength(1));
      expect(heard.refused, [Status.permissionDenied]);
    });

    test('busy is tried again', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(Status.busy, '');
      svc.follow('wy/central/dataflows/tank');
      await settle(40);
      expect(
        api.calls.where((c) => c.action == 'watch').length,
        greaterThan(1),
      );
      expect(heard.refused, isEmpty);
    });

    test('a stream that fails at once backs off', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(Status.timeout, 'slow');
      svc.follow('wy/central/dataflows/tank');
      await settle(60);
      final n = api.calls.where((c) => c.action == 'watch').length;
      expect(n, inInclusiveRange(2, 5), reason: '10, 20, 20 ms apart');
    });
  });
}

class _Listener implements FlowWatchServiceListener {
  final batches = <(Map<String, LiveValue>, bool)>[];
  final refused = <Status?>[];
  final redeployed = <int?>[];

  @override
  void onPorts(Map<String, LiveValue> changed, {required bool reset}) =>
      batches.add((changed, reset));

  @override
  void onRefused(Status? status) => refused.add(status);

  @override
  void onRedeployed(int? version) => redeployed.add(version);
}

extension on Map<String, LiveValue> {
  LiveValue? get(String k) => this[k];
}
