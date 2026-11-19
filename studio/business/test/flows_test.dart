import 'dart:typed_data';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/add_block_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/decode/node_type.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/error_hint.dart';
import 'package:models/flow_problem_kind.dart';
import 'package:models/unreadable_part.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/block_types.dart';
import 'support/fake_wyrm.dart';

final def = Value.from({
  'id': 'tank',
  'version': 3,
  'description': 'tank level',
  'nodes': {
    'level': {'type': 'subscribe', 'key': 'downstream/modbus/tank/level'},
    'scale': {'type': 'scale', 'input_max': 4095},
    'out': {'type': 'publish', 'key': 'storage/tank/level'},
  },
  'edges': [
    ['level.out', 'scale.in'],
    ['scale.out', 'out.in'],
  ],
  'layout': {
    'level': [10, 20],
  },
});

final types = Value.from([
  {
    'type': 'subscribe',
    'category': 'sources',
    'inputs': <String>[],
    'outputs': ['out'],
    'params': [
      {'name': 'key', 'type': 'string', 'required': true},
    ],
  },
  {
    'type': 'scale',
    'category': 'math',
    'inputs': ['in', 'in.input_max'],
    'outputs': ['out'],
    'params': [
      {'name': 'input_max', 'type': 'number', 'default': 1},
    ],
  },
  {
    'type': 'expression',
    'category': 'logic',
    'inputs': <String>[],
    'outputs': ['out'],
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['a'],
    },
    'params': <Object>[],
  },
]);

void main() {
  test('a definition round-trips through the draft, layout kept', () {
    final d = flowDraftOf('tank', def);

    expect(d.version, 3);
    expect(d.blocks['level']!.x, 10);
    expect(d.blocks['scale']!.cfg['input_max'], 4095);
    expect(d.edges.first.fromPort, 'out');
    expect(d.rest['description'], 'tank level');

    final back = toDart(defOf(d, 4))! as Map<String, Object?>;
    expect(back['version'], 4);
    expect((back['nodes']! as Map)['scale'], {
      'type': 'scale',
      'input_max': 4095,
    });
    expect(back['edges'], [
      ['level.out', 'scale.in'],
      ['scale.out', 'out.in'],
    ]);
    expect((back['layout']! as Map)['level'], [10, 20]);
    expect(back['description'], 'tank level');
    expect(flowKeysOf(d).reads, ['downstream/modbus/tank/level']);
    expect(flowKeysOf(d).writes, ['storage/tank/level']);
  });

  test('a flow that sets gets maxperm write', () {
    final d = flowDraftOf(
      'x',
      Value.from({
        'nodes': {
          's': {'type': 'set', 'key': 'a'},
        },
      }),
    );
    expect(
      (toDart(defOf(d, 1))! as Map)['permissions'],
      {'maxperm': 'write'},
    );
  });

  test('dyn ports come from the parameter, or its defaults', () {
    final t = nodeTypeOf((types as VArray).v[2]).orWarn('test')!;
    final d = flowDraftOf(
      'x',
      Value.from({
        'nodes': {
          'e': {
            'type': 'expression',
            'inputs': ['x', 'y'],
          },
        },
      }),
    );
    expect(portsOf(t, d.blocks['e']!).inputs, ['in.x', 'in.y']);
    final e = flowDraftOf(
      'x',
      Value.from({
        'nodes': {
          'e': {'type': 'expression'},
        },
      }),
    );
    expect(portsOf(t, e.blocks['e']!).inputs, ['in.a']);
  });

  group('the editor', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    setUp(() async {
      final login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());
      api
        ..invokes['wy/central/dataflows ▸ node_types'] = [types]
        ..invokes['wy/central/dataflows/tank ▸ history'] = [
          Value.from([toDart(def)]),
        ]
        ..invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': true}),
        ]
        ..invokes['wy/central/dataflows ▸ deploy'] = [const VNull()];
    });

    test('a definition Studio cannot read is said; the editor keeps what '
        'it had, never an empty draft a deploy would write over', () async {
      await s.dispatchAndWait(LoadFlowAction('tank'));
      final held = s.state.flowEditor.draft;
      api.invokes['wy/central/dataflows/tank ▸ history'] = [
        Value.from([
          {
            'version': 4,
            'nodes': {'a': <String, Object?>{}},
          },
        ]),
      ];
      final status = await s.dispatchAndWait(LoadFlowAction('tank'));
      expect(status.originalError, isA<StudioException>());
      // the refusal names the flow and the decoder's field; the app words it
      expect(
        (status.originalError! as StudioException).error.hint,
        isA<ErrorHintUnreadable>()
            .having((h) => h.part, 'part', UnreadablePart.flowDef)
            .having((h) => h.name, 'flow', 'tank')
            .having((h) => h.field, 'field', 'nodes.a.type'),
      );
      expect(s.state.flowEditor.draft, held);
      expect(s.state.flowEditor.version, 3);

      // Another flow that does not read: the one held goes, and nothing
      // is there to deploy under its id.
      api.invokes['wy/central/dataflows/other ▸ history'] = [
        Value.from([
          {'edges': 'a.out'},
        ]),
      ];
      final other = await s.dispatchAndWait(LoadFlowAction('other'));
      expect(other.originalError, isA<StudioException>());
      expect(s.state.flowEditor.flowId, 'other');
      expect(s.state.flowEditor.draft, isNull);
      expect(s.state.flowEditor.deployed, isNull);
      await s.dispatchAndWait(DeployFlowAction());
      expect(
        api.calls.where((c) => c.action == 'deploy'),
        isEmpty,
        reason: 'no draft, no deploy',
      );
    });

    test('a definition holding bytes does not open: the refusal names the '
        'field', () async {
      api.invokes['wy/central/dataflows/raw ▸ history'] = [
        Value.from([
          {
            'version': 1,
            'nodes': {
              'a': {
                'type': 'scale',
                'k': Uint8List.fromList([1, 2]),
              },
            },
          },
        ]),
      ];
      final status = await s.dispatchAndWait(LoadFlowAction('raw'));
      expect(status.originalError, isA<StudioException>());
      // the refusal names the flow and the decoder's field; the app words it
      expect(
        (status.originalError! as StudioException).error.hint,
        isA<ErrorHintUnreadable>()
            .having((h) => h.part, 'part', UnreadablePart.flowDef)
            .having((h) => h.name, 'flow', 'raw')
            .having((h) => h.field, 'field', 'nodes.a.k'),
      );
      expect(s.state.flowEditor.draft, isNull);
    });

    test(
      "validate: the engine's words become a problem with the block "
      'they name; an answer of another shape is one Studio cannot read',
      () async {
        await s.dispatchAndWait(LoadFlowAction('tank'));
        api.invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': false, 'error': 'scale: in.zz is no input'}),
        ];
        await s.dispatchAndWait(ValidateFlowAction());
        expect(
          s.state.flowEditor.problems.single.message,
          'scale: in.zz is no input',
        );
        expect(s.state.flowEditor.problems.single.block, 'scale');
        api.invokes['wy/central/dataflows ▸ validate'] = [const VArray([])];
        await s.dispatchAndWait(ValidateFlowAction());
        expect(s.state.flowEditor.problems.single.kind, FlowProblemKind.unread);
      },
    );

    test('loads, edits and deploys version + 1', () async {
      await s.dispatchAndWait(LoadFlowAction('tank'));
      expect(s.state.flowEditor.draft!.blocks.length, 3);
      expect(
        s.state.flowEditor.types.map((t) => t.type.wire),
        containsAll(['scale', 'subscribe']),
      );

      s
        ..dispatchSync(AddBlockAction(bt('scale'), 300, 40))
        ..dispatchSync(ConnectPortsAction('level', 'out', 'scale1', 'in'));
      final d = s.state.flowEditor.draft!;
      expect(
        d.blocks['scale1']!.cfg['input_max'],
        isNull,
        reason: 'only choice defaults are written; the block shows the rest',
      );
      expect(d.edges.where((e) => e.to == 'scale1'), hasLength(1));
      expect(s.state.flowEditor.dirty, isTrue);

      s.dispatchSync(ConnectPortsAction('scale', 'out', 'scale1', 'in'));
      expect(
        s.state.flowEditor.draft!.edges
            .where((e) => e.to == 'scale1')
            .single
            .from,
        'scale',
        reason: 'an input takes one wire',
      );

      s.dispatchSync(RemoveBlocksAction(const ['scale1']));
      expect(
        s.state.flowEditor.draft!.edges.where((e) => e.to == 'scale1'),
        isEmpty,
      );

      await s.dispatchAndWait(DeployFlowAction());
      final sent = api.calls.lastWhere((c) => c.action == 'deploy').args!;
      expect(integer(sent['def']!['version']), 4);
      expect(s.state.flowEditor.version, 4);
      expect(s.state.flowEditor.dirty, isFalse);
    });
  });
}
