import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/move_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/preview_flow_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/redux/services/flow_preview/flow_preview.dart';
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

import 'support/fake_wyrm.dart';

// The catalog as the demo's broker answers `dataflows` ▸ `node_types`
// (2026-11-08, ADR 0038 §2), the entries these tests read.
final List<Map<String, Object>> live = [
  {
    'type': 'number',
    'category': 'Variables',
    'echo_inputs': true,
    'inputs': ['in'],
    'outputs': ['out'],
    'params': [
      {
        'name': 'value',
        'type': 'number',
        'default': 0,
        'echo': true,
        'required': false,
      },
    ],
    'port_types': {'in': 'any', 'out': 'number', 'value': 'number'},
  },
  {
    'type': 'string',
    'category': 'Variables',
    'echo_inputs': true,
    'inputs': ['in'],
    'outputs': ['out'],
    'params': [
      {
        'name': 'value',
        'type': 'string',
        'default': '',
        'echo': true,
        'editor': 'textarea',
        'required': false,
      },
    ],
    'port_types': {'in': 'any', 'out': 'any', 'value': 'any'},
  },
  {
    'type': 'bool',
    'category': 'Variables',
    'echo_inputs': true,
    'inputs': ['in'],
    'outputs': ['out'],
    'params': [
      {
        'name': 'value',
        'type': 'bool',
        'default': false,
        'echo': true,
        'required': false,
      },
    ],
    'port_types': {'in': 'any', 'out': 'bool', 'value': 'bool'},
  },
  {
    'type': 'const',
    'category': 'Sources',
    'inputs': <String>[],
    'outputs': ['out'],
    'params': [
      {'name': 'value', 'type': 'dynamic', 'echo': true, 'required': true},
    ],
    'port_types': {'out': 'any', 'value': 'any'},
  },
  {
    'type': 'concat',
    'category': 'Text',
    'dyn_inputs': {
      'default': ['0', '1'],
      'param': 'inputs',
      'prefix': 'in.',
    },
    'echo_inputs': true,
    'inputs': <String>[],
    'outputs': ['out'],
    'params': [
      {'name': 'strict', 'type': 'bool', 'default': false, 'echo': true},
      {
        'name': 'inputs',
        'type': 'array',
        'default': ['0', '1'],
        'echo': true,
      },
    ],
    'port_types': {
      'in.0': 'any',
      'in.1': 'any',
      'inputs': 'any',
      'out': 'any',
      'strict': 'bool',
    },
  },
  {
    'type': 'hub',
    'category': 'Logic',
    'dyn_inputs': {
      'default': ['0', '1'],
      'param': 'inputs',
      'prefix': 'in.',
    },
    'echo_inputs': true,
    'inputs': <String>[],
    'outputs': ['out', 'index', 'on_change'],
    'params': [
      {'name': 'ignore_null', 'type': 'bool', 'default': true, 'echo': true},
      {
        'name': 'inputs',
        'type': 'array',
        'default': ['0', '1'],
        'echo': true,
      },
    ],
  },
  {
    'type': 'set',
    'category': 'Outputs',
    'inputs': ['in'],
    'outputs': <String>[],
    'params': [
      {'name': 'path', 'type': 'string', 'required': true},
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

void main() {
  final types = catalog(live);

  group('one field = one entity (owner decision 2026-11-08)', () {
    test('a variable is one field Value: input in, output out', () {
      for (final type in ['number', 'string', 'bool']) {
        final f = fieldsOf(types[type], block('v', type));
        expect(f, hasLength(1), reason: type);
        final v = f.single;
        expect(
          (v.label, v.name, v.kind, v.inPort, v.outPort, v.variable),
          ('Value', 'value', FieldKind.param, 'in', 'out', true),
          reason: type,
        );
        // Older definitions may have wired the echoes: they land here too.
        expect(v.outAliases, ['value', 'in']);
        expect(v.sends('value') && v.sends('in') && v.sends('out'), isTrue);
      }
    });

    test('const is one field Value with no input', () {
      final v = fieldsOf(types['const'], block('c', 'const')).single;
      expect((v.label, v.inPort, v.outPort), ('Value', null, 'out'));
    });

    test('concat: Input 1, Input 2, then Strict, then Output (as DGLux)', () {
      final rows = rowsOf(types['concat'], block('c', 'concat'));
      expect(
        [for (final r in rows) r.label],
        ['Input 1', 'Input 2', 'Strict', 'Output'],
      );
      final in0 = rows.first;
      expect((in0.inPort, in0.outPort), ('in.0', 'in.0'));
      final strict = rows[2];
      expect((strict.inPort, strict.outPort), (null, 'strict'));
      expect((rows.last.inPort, rows.last.outPort), (null, 'out'));
    });

    test('hub: inputs, then Ignore null, then its outputs', () {
      final rows = rowsOf(types['hub'], block('h', 'hub'));
      expect(
        [for (final r in rows) r.name],
        ['in.0', 'in.1', 'ignore_null', 'out', 'index', 'on_change'],
      );
    });

    test('a variable shows what it sends, else what comes in, else its '
        'value', () {
      final b = block('limit', 'number', {'value': 25});
      final f = fieldsOf(types['number'], b).single;
      final free = FlowDraft(id: 'x', blocks: {'limit': b}.lock);
      expect(fieldValue(b, f, free, (_) => null).text, '25');
      final out = {
        portKey('out', 'limit', 'out'): LiveValue(
          time: DateTime(2026),
          value: 30,
        ),
      };
      expect(fieldValue(b, f, free, out.get).text, '30');
      final bound = free.copyWith(
        edges: [
          const FlowEdge(from: 't', fromPort: 'out', to: 'limit', toPort: 'in'),
        ].lock,
      );
      final none = fieldValue(b, f, bound, (_) => null);
      expect((none.text, none.bound), ('', true), reason: 'not the typed 25');
      final inSample = {
        portKey('in', 'limit', 'in'): LiveValue(
          time: DateTime(2026),
          value: 21.5,
        ),
      };
      final v = fieldValue(b, f, bound, inSample.get);
      expect((v.text, v.bound), ('21.5', true));
    });

    test('the preview definition leaves the layout out', () {
      final b = block('limit', 'number', {'value': 25});
      final d = FlowDraft(id: '', blocks: {'limit': b}.lock);
      final moved = d.copyWith(
        blocks: {'limit': b.copyWith(x: 400, y: 300)}.lock,
      );
      expect(previewDefOf(d), previewDefOf(moved));
      expect(defOf(d, 0) == defOf(moved, 0), isFalse);
      expect((toDart(previewDefOf(d))! as Map)['id'], 'draft');
    });
  });

  group('the preview service', () {
    late FakeWyrmApi api;
    late _Heard heard;
    late FlowPreviewService svc;
    const at = 'wy/central/dataflows';
    const id = '$at ▸ preview';
    Value def(int v) => Value.from({
      'id': 'tank',
      'version': 0,
      'nodes': {
        'limit': {'type': 'number', 'value': v},
      },
      'edges': <Object>[],
    });

    setUp(() {
      api = FakeWyrmApi()..streamed.add(id);
      heard = _Heard();
      svc = FlowPreviewService(
        listener: heard,
        debounce: const Duration(milliseconds: 10),
        flushEvery: const Duration(milliseconds: 1),
        retryFirst: const Duration(milliseconds: 5),
        retryMax: const Duration(milliseconds: 20),
      )..attach(api);
    });

    tearDown(() => svc.dispose());

    Future<void> settle([int ms = 30]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    Iterable<Call> previews() => api.calls.where((c) => c.action == 'preview');

    test('edits are debounced: one preview, with the last draft', () async {
      svc
        ..show(at, def(1))
        ..show(at, def(2))
        ..show(at, def(3));
      await settle();
      expect(previews(), hasLength(1));
      expect(
        toDart(previews().single.args),
        {'def': toDart(def(3)), 'max_hz': 4},
      );
    });

    test('the same draft again (a block moved) does not reopen', () async {
      svc.show(at, def(1));
      await settle();
      svc.show(at, Value.from(toDart(def(1))));
      await settle();
      expect(previews(), hasLength(1));
    });

    test(
      'an edit ends the preview before and opens one of the new draft',
      () async {
        svc.show(at, def(1));
        await settle();
        // ignore: close_sinks, the service ends it.
        final first = api.opened[id]!.single;
        expect(first.hasListener, isTrue);
        svc.show(at, def(2));
        expect(first.hasListener, isFalse, reason: 'ended at once');
        await settle();
        expect(api.opened[id], hasLength(2));
        expect(
          toDart(previews().last.args),
          containsPair('def', toDart(def(2))),
        );
      },
    );

    test('rows and sinks (full keys; a row of sinks alone) reach the '
        'listener', () async {
      svc.show(at, def(70));
      await settle();
      heard.values.clear();
      api.opened[id]!.single.add(
        Value.from({
          't': 1700000000000000,
          'snapshot': true,
          'nodes': {
            'limit': {
              'in': <String, Object>{},
              'out': {
                'out': [70, 0],
              },
              'params': {'value': 70},
            },
          },
          'sinks': [
            {
              'node': 'knob',
              'op': 'set',
              // The full key it would write (ADR 0038 §5).
              'key': 'wy/central/downstream/mockdev/bench/rig1/knob/~set',
              'value': 70.7,
            },
          ],
        }),
      );
      await settle();
      final (ports, sinks, reset) = heard.values.single;
      expect(reset, isTrue);
      expect(ports['out:limit.out']!.value, 70);
      expect(sinks['knob']!.value, 70.7);

      // A row of sinks alone: a change row with `nodes: {}`.
      heard.values.clear();
      api.opened[id]!.single.add(
        Value.from({
          't': 1700000001000000,
          'snapshot': false,
          'nodes': <String, Object>{},
          'sinks': [
            {
              'node': 'knob',
              'op': 'set',
              'key': 'wy/central/downstream/mockdev/bench/rig1/knob/~set',
              'value': 71,
            },
          ],
        }),
      );
      await settle();
      final (p2, s2, r2) = heard.values.single;
      expect(p2, isEmpty);
      expect(r2, isFalse, reason: 'the ports stay');
      expect(s2['knob']!.value, 71);
    });

    test('an end at its ttl opens again soon', () async {
      final svc = FlowPreviewService(
        listener: heard,
        debounce: const Duration(milliseconds: 10),
        flushEvery: const Duration(milliseconds: 1),
        retryFirst: const Duration(milliseconds: 5),
        ttl: Duration.zero,
      )..attach(api);
      addTearDown(svc.dispose);
      svc.show(at, def(1));
      await settle();
      final before = api.opened[id]!.length;
      api.opened[id]!.last.add(
        Value.from({'t': 1, 'snapshot': true, 'nodes': <String, Object>{}}),
      );
      await api.opened[id]!.last.close();
      await settle();
      expect(api.opened[id], hasLength(before + 1), reason: 'opened again');
    });

    test('ended early by a newer preview of the same user: no error, the '
        'values stay, opened again later', () async {
      // The broker keeps 2 previews per subject; a third ends the oldest.
      final svc = FlowPreviewService(
        listener: heard,
        debounce: const Duration(milliseconds: 10),
        flushEvery: const Duration(milliseconds: 1),
        retryFirst: const Duration(milliseconds: 5),
        retryMax: const Duration(milliseconds: 80),
      )..attach(api);
      addTearDown(svc.dispose);
      svc.show(at, def(1));
      await settle();
      final before = api.opened[id]!.length;
      api.opened[id]!.last.add(
        Value.from({
          't': 1,
          'snapshot': true,
          'nodes': {
            'limit': {
              'in': <String, Object>{},
              'out': {
                'out': [1, 0],
              },
              'params': {'value': 1},
            },
          },
        }),
      );
      await settle();
      heard.values.clear();
      await api.opened[id]!.last.close();
      await settle();
      expect(api.opened[id], hasLength(before), reason: 'not at once');
      expect(heard.values, isEmpty, reason: 'its values stay');
      expect(heard.invalid, isEmpty);
      expect(heard.off, isEmpty);
      await settle(100);
      expect(api.opened[id], hasLength(before + 1), reason: 'opened later');
    });

    test('an invalid draft is told with the compiler message; its values '
        'stay until a draft runs again', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(
        Status.invalidParameter,
        'edge limit.out → x.in: no node x',
      );
      svc.show(at, def(1));
      await settle();
      expect(heard.invalid, ['edge limit.out → x.in: no node x']);
      expect(previews(), hasLength(1), reason: 'not asked again');
      expect(heard.values.where((v) => v.$3), isEmpty, reason: 'no reset');

      api.errors.remove(id);
      api.streamed.add(id);
      svc.show(at, def(2));
      await settle();
      api.opened[id]!.single.add(
        Value.from({'t': 1, 'snapshot': true, 'nodes': <String, Object>{}}),
      );
      await settle();
      expect(heard.invalid.last, isNull, reason: 'it runs again');
    });

    test('a broker without the action: not asked again, quietly', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(Status.notFound, 'action preview');
      svc.show(at, def(1));
      await settle();
      svc.show(at, def(2));
      await settle();
      expect(previews(), hasLength(1));
      expect(svc.off, isTrue);
      expect(heard.off, [Status.notFound]);
    });

    test('busy is tried again later', () async {
      api.streamed.remove(id);
      api.errors[id] = WyrmException.of(Status.busy, '');
      svc.show(at, def(1));
      await settle(60);
      expect(previews().length, greaterThan(1));
      expect(heard.off, isEmpty);
    });

    test('stopping drops the values', () async {
      svc.show(at, def(1));
      await settle();
      heard.values.clear();
      svc.show(null, null);
      await settle();
      expect(heard.values.single.$3, isTrue);
      expect(api.opened[id]!.single.hasListener, isFalse);
    });
  });

  group('the editor switches between preview and watch', () {
    late FakeWyrmApi api;
    late Store<AppState> s;
    final def = Value.from({
      'id': 'tank',
      'version': 2,
      'nodes': {
        'limit': {'type': 'number', 'value': 25},
      },
      'edges': <Object>[],
      'layout': {
        'limit': [40, 40],
      },
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
        ..invokes['wy/central/dataflows ▸ node_types'] = [Value.from(live)]
        ..invokes['wy/central/dataflows/tank ▸ history'] = [
          Value.from([toDart(def)]),
        ]
        ..streamed.add('wy/central/dataflows ▸ preview');
      await s.dispatchAndWait(LoadFlowAction('tank'));
    });

    tearDown(() => s.dispatchSync(PreviewFlowAction(stop: true)));

    Future<void> debounce() =>
        Future<void>.delayed(const Duration(milliseconds: 400));

    Iterable<Call> previews() => api.calls.where((c) => c.action == 'preview');

    test(
      'the deployed draft is not previewed; an edit is; moving is not',
      () async {
        s.dispatchSync(PreviewFlowAction());
        await debounce();
        expect(previews(), isEmpty, reason: 'the watch shows it');

        s
          ..dispatchSync(MoveBlocksAction(const {'limit': (200, 200)}))
          ..dispatchSync(PreviewFlowAction());
        await debounce();
        expect(previews(), isEmpty, reason: 'the layout runs nothing');

        s
          ..dispatchSync(SetBlockParamAction('limit', 'value', 30))
          ..dispatchSync(PreviewFlowAction());
        await debounce();
        expect(previews(), hasLength(1));
        final sent = (toDart(previews().single.args)! as Map)['def'] as Map;
        expect((sent['nodes'] as Map)['limit'], {
          'type': 'number',
          'value': 30,
        });
        expect(sent.containsKey('layout'), isFalse);
      },
    );

    test(
      'back to the deployed version: the preview ends, its values go',
      () async {
        s
          ..dispatchSync(SetBlockParamAction('limit', 'value', 30))
          ..dispatchSync(PreviewFlowAction());
        await debounce();
        api.opened['wy/central/dataflows ▸ preview']!.single.add(
          Value.from({
            't': 1,
            'snapshot': true,
            'nodes': {
              'limit': {
                'in': <String, Object>{},
                'out': {
                  'out': [30, 0],
                },
                'params': {'value': 30},
              },
            },
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(s.state.flowEditor.previewPorts['out:limit.out']?.value, 30);

        s
          ..dispatchSync(SetBlockParamAction('limit', 'value', 25))
          ..dispatchSync(PreviewFlowAction());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(s.state.flowEditor.previewPorts, isEmpty);
        expect(
          api.opened['wy/central/dataflows ▸ preview']!.single.hasListener,
          isFalse,
        );
      },
    );

    test(
      'a broker without preview: the editor falls back, says nothing',
      () async {
        api
          ..streamed.remove('wy/central/dataflows ▸ preview')
          ..errors['wy/central/dataflows ▸ preview'] = WyrmException.of(
            Status.notFound,
            'action preview',
          );
        s
          ..dispatchSync(SetBlockParamAction('limit', 'value', 30))
          ..dispatchSync(PreviewFlowAction());
        await debounce();
        expect(s.state.flowEditor.previewOff, 'not_found');
        expect(s.state.flowEditor.previewError, isNull);
        s
          ..dispatchSync(SetBlockParamAction('limit', 'value', 31))
          ..dispatchSync(PreviewFlowAction());
        await debounce();
        expect(previews(), hasLength(1), reason: 'not asked again');
      },
    );
  });
}

class _Heard implements FlowPreviewServiceListener {
  final values = <(Map<String, LiveValue>, Map<String, LiveValue>, bool)>[];
  final invalid = <String?>[];
  final off = <Status?>[];

  @override
  void onValues(
    Map<String, LiveValue> ports,
    Map<String, LiveValue> sinks, {
    required bool reset,
  }) => values.add((ports, sinks, reset));

  @override
  void onInvalid(String? message) => invalid.add(message);

  @override
  void onOff(Status? status) => off.add(status);
}

extension on Map<String, LiveValue> {
  LiveValue? get(String k) => this[k];
}
