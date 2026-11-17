import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/add_block_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/create_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/enter_block_action.dart';
import 'package:business/redux/flow_editor/actions/leave_block_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/paste_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/place_library_block_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/remove_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/rename_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/resize_block_ports_action.dart';
import 'package:business/redux/flow_editor/actions/retrieve_block_library_action.dart';
import 'package:business/redux/flow_editor/actions/save_block_to_library_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_operand_value_action.dart';
import 'package:business/redux/flow_editor/actions/set_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/trigger_block_action.dart';
import 'package:business/redux/flow_editor/actions/undo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/update_block_from_library_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/flows/actions/retrieve_flows_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/decode/block_def.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/flow_def.dart';
import 'package:business/wyrm/decode/node_type.dart';
import 'package:business/wyrm/failures.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/action_info.dart';
import 'package:models/block_type.dart';
import 'package:models/error_hint.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/library_off.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:models/param_spec.dart';
import 'package:models/port_end.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/block_types.dart';
import 'support/catalog_0221.dart';
import 'support/catalog_0226.dart';
import 'support/fake_wyrm.dart';

// Wave 2 of the flow editor (flow-editor.md §17–§20, ADR 0040, owner
// requirements 2026-11-09): a key bound inside a scope, the tree's points
// and actions as blocks, the action block's behaviours and its `trigger`,
// custom blocks with their library, and what an older broker turns off.

final Map<String, NodeType> types = {
  for (final t in catalog0226())
    t['type']! as String: nodeTypeOf(Value.from(t)).orWarn('test')!,
};

/// `name → concat → path`, a `subscribe` of a fixed point, and a mean of
/// two points published.
final Map<String, Object> line = {
  'id': 'line',
  'version': 2,
  'nodes': {
    'name': {'type': 'string', 'value': 'pump1'},
    'path': {
      'type': 'concat',
      'values': {'in.0': 'downstream/modbus/line1/'},
    },
    'level': {'type': 'subscribe', 'key': 'downstream/modbus/line1/level'},
    'a': {'type': 'subscribe', 'key': 'downstream/modbus/line1/a'},
    'b': {'type': 'subscribe', 'key': 'downstream/modbus/line1/b'},
    'sum': {'type': 'add'},
    'half': {
      'type': 'divide',
      'values': {'in.1': 2},
    },
    'mean': {'type': 'publish', 'node': 'mean'},
  },
  'edges': [
    ['name.out', 'path.in.1'],
    ['a.out', 'sum.in.0'],
    ['b.out', 'sum.in.1'],
    ['sum.out', 'half.in.0'],
    ['half.out', 'mean.in'],
  ],
  'layout': {
    'name': [40, 40],
    'path': [300, 40],
    'level': [560, 40],
    'a': [40, 300],
    'b': [40, 420],
    'sum': [300, 300],
    'half': [560, 300],
    'mean': [820, 300],
  },
};

FlowDraft draft() => flowDraftOf('line', Value.from(line));

List<String> rowIds(FlowDraft d, String id, {Map<String, NodeType>? by}) {
  final all = {
    for (final t in typesWithBlocks(types.values.toIList(), d)) t.type: t,
    ...?by,
  };
  return [
    for (final f in rowsOf(
      all[d.blocks[id]!.type],
      d.blocks[id]!,
      edges: d.edges,
    ))
      f.id.key,
  ];
}

/// Custom block [name] of [d] as the definition writes it.
Map<String, Object?> defJson(FlowDraft d, String name) =>
    blockDefJsonOf(blockDefsOf(d)[name]!);

/// The block definition [json], decoded.
BlockDef blockDef(Map<String, Object?> json) => switch (blockDefOf(json)) {
  Valid(:final value) => value,
  final Invalid<BlockDef> i => throw StateError('$i'),
};

Map<String, Object?> defMap(FlowDraft d) =>
    toDart(defOf(d, d.version))! as Map<String, Object?>;

/// The library's `mean` block: `(a + b) / n`, and `scaled` which uses it.
final Map<String, Object?> libMean = {
  'description': 'The mean of two values',
  'inputs': [
    {'name': 'a', 'to': 'sum.in.0'},
    {'name': 'b', 'to': 'sum.in.1'},
    {'name': 'n', 'to': 'half.in.1', 'default': 2},
  ],
  'outputs': [
    {'name': 'out', 'from': 'half.out'},
  ],
  'nodes': {
    'sum': {'type': 'add'},
    'half': {'type': 'divide'},
  },
  'edges': [
    ['sum.out', 'half.in.0'],
  ],
};
final Map<String, Object?> libScaled = {
  'inputs': [
    {'name': 'x', 'to': 'm.a'},
  ],
  'outputs': [
    {'name': 'out', 'from': 'm.out'},
  ],
  'nodes': {
    'm': {'type': 'block:mean'},
  },
  'edges': <Object>[],
};

void main() {
  group('what the broker can do', () {
    test('a catalog with ADR 0040 has scopes, trigger and argument ports; '
        'custom blocks once the library answered', () {
      expect(
        flowCapsOf(types.values, libraryOff: const LibraryOff.unread()),
        const FlowCaps(scopes: true, trigger: true, args: true),
      );
      expect(
        flowCapsOf(types.values),
        const FlowCaps(scopes: true, trigger: true, args: true, blocks: true),
      );
      expect(types['subscribe']!.params.first.scope, 'key_scope');
      expect(types['invoke']!.dynInKeys, isTrue);
      expect(types['invoke']!.trigger, isTrue);
      expect(types['subscribe']!.trigger, isFalse);
    });

    test('an older catalog has none of it', () {
      final old = [
        for (final t in catalog0221())
          nodeTypeOf(Value.from(t)).orWarn('test')!,
      ];
      expect(
        flowCapsOf(
          old,
          libraryOff: LibraryOff.refused(StatusCode.of(Status.notFound)),
        ),
        const FlowCaps(),
      );
    });

    test('on an older broker a key field takes no wire, and says it needs a '
        'newer broker', () {
      final old = nodeTypeOf(
        Value.from({
          'type': 'subscribe',
          'inputs': <String>[],
          'outputs': ['out'],
          'params': [
            {'name': 'key', 'type': 'string', 'required': true},
          ],
        }),
      ).orWarn('test')!;
      final d = draft();
      final key = fieldsOf(
        old,
        d.blocks['level']!,
      ).firstWhere((f) => f.id.key == 'p:key');
      expect(key.inPort, isNull);
      expect(
        bindRefusal(
          byType({...types, 'subscribe': old}),
          d,
          fromBlock: 'path',
          fromPort: 'out',
          toBlock: 'level',
          to: key,
        )?.reason,
        BindRefusal.needsBroker,
      );
      // Its rows are the ones of before: the point alone.
      expect(
        [for (final f in rowsOf(old, d.blocks['level']!)) f.id.key],
        ['out:out'],
      );
    });
  });

  group('a key from a binding', () {
    test('the key is a field with a left port; its scope and the error '
        'output show once a wire feeds it', () {
      var d = draft();
      expect(rowIds(d, 'level'), ['p:key', 'out:out']);
      final key = fieldsOf(
        types['subscribe'],
        d.blocks['level']!,
      ).firstWhere((f) => f.id.key == 'p:key');
      expect(key.inPort, 'in.key');
      expect(key.label, 'Point');
      expect(
        bindRefusal(
          byType(types),
          d,
          fromBlock: 'path',
          fromPort: 'out',
          toBlock: 'level',
          to: key,
        ),
        isNull,
      );
      d = d.copyWith(
        edges: d.edges.add(
          const FlowEdge(
            from: 'path',
            fromPort: 'out',
            to: 'level',
            toPort: 'in.key',
          ),
        ),
      );
      expect(rowIds(d, 'level'), [
        'p:key',
        'p:key_scope',
        'out:out',
        'out:error',
      ]);
      final scope = fieldsOf(
        types['subscribe'],
        d.blocks['level']!,
        edges: d.edges,
      ).firstWhere((f) => f.id.key == 'p:key_scope');
      expect(scope.label, 'Scope');
      expect(scope.inPort, isNull);
      expect(scope.outPort, isNull, reason: 'read on the block, feeds nothing');
    });

    test("the suggestion is the key's parent and all below it", () {
      expect(
        scopeSuggestion('downstream/modbus/line1/level'),
        'downstream/modbus/line1/**',
      );
      expect(
        scopeSuggestion('wy/plant/storage/tank/level', site: 'plant'),
        'storage/tank/**',
      );
      expect(scopeSuggestion('downstream/level'), 'downstream/**');
      expect(scopeSuggestion(null), 'downstream/**');
      expect(scopeSuggestion('sys/links/x'), 'downstream/**');
    });

    test(
      'a scope lies inside downstream, dataflows or storage of the site',
      () {
        String? bad(String s) => scopeProblem(s, site: 'plant')?.name;
        expect(bad('downstream/modbus/line1/**'), isNull);
        expect(bad('storage/**'), isNull);
        expect(bad('wy/plant/dataflows/*/nodes/*'), isNull);
        expect(bad(''), 'empty');
        expect(bad('sys/**'), 'section');
        expect(bad('**'), 'section');
        expect(bad('*/modbus/**'), 'section');
        expect(bad('wy/other/downstream/**'), 'otherSite');
        expect(bad('downstream/a b/**'), 'segment');
        expect(bad('downstream/x/~meta'), 'segment');
        expect(bad('downstream//x'), 'segment');
      },
    );
  });

  group('the tree as blocks', () {
    const caps = FlowCaps(scopes: true, trigger: true, args: true);
    final ramp = ActionInfo(
      name: 'ramp',
      level: Perm.write,
      params: [
        const ParamSpec(name: 'target', type: TypeCode.number, required: true),
        const ParamSpec(
          name: 'ramp_s',
          type: TypeCode.number,
          defaultValue: 30,
        ),
        const ParamSpec(
          name: 'mode',
          type: TypeCode.enum_,
          choices: IListConst(['linear', 'step']),
        ),
      ].lock,
    );

    test('a value reads, a writable value may write', () {
      final read = blockOfEntry(
        const PointPick('wy/plant/downstream/plc/level'),
      )!;
      expect(read.type.wire, 'subscribe');
      expect(read.cfg, {'key': 'downstream/plc/level'});
      final write = blockOfEntry(
        const PointPick('wy/plant/downstream/plc/fan'),
        write: true,
      )!;
      expect(write.type.wire, 'set');
      expect(write.cfg, {'path': 'downstream/plc/fan'});
      expect(blockOfEntry(EnginePick(bt('scale'))), isNull);
    });

    test('an action is an invoke with one argument per parameter; the '
        'required ones are rows of the block', () {
      final e = blockOfEntry(
        const ActionPick('wy/plant/downstream/plc/pump', 'ramp'),
        action: ramp,
        caps: caps,
      )!;
      expect(e.type.wire, 'invoke');
      expect(e.cfg, {
        'path': 'downstream/plc/pump',
        'action': 'ramp',
        'args': {'target': null, 'ramp_s': 30, 'mode': null},
      });
      expect(e.pins, {
        const FieldId.arg('ramp_s'): false,
        const FieldId.arg('mode'): false,
      });
      final b = FlowBlock(
        id: 'ramp1',
        type: bt('invoke'),
        cfg: e.cfg.lock,
        pins: {for (final p in e.pins.entries) p.key.key: p.value}.lock,
      );
      final fields = fieldsOf(types['invoke'], b, actionParams: ramp.params);
      final target = fields.firstWhere((f) => f.id.key == 'arg:target');
      expect(target.inPort, 'arg.target');
      expect(target.argSpec?.required, isTrue);
      expect(
        [for (final f in rowsOf(types['invoke'], b)) f.id.key],
        ['arg:target', 'in:trigger', 'out:ok', 'out:error'],
      );
      // The argument's own type is its editor.
      const none = IListConst<FlowEdge>([]);
      expect(
        fieldEditOf(
          b,
          fields.firstWhere((f) => f.id.key == 'arg:mode'),
          none,
        ).edit,
        FieldEdit.choice,
      );
      expect(fieldEditOf(b, target, none).edit, FieldEdit.number);
    });

    test('an action without parameters, and on a broker without argument '
        'ports', () {
      expect(
        blockOfEntry(
          const ActionPick('wy/plant/downstream/plc/pump', 'stop'),
          caps: caps,
        )!.cfg,
        {'path': 'downstream/plc/pump', 'action': 'stop'},
      );
      final old = blockOfEntry(
        const ActionPick('wy/plant/downstream/plc/pump', 'ramp'),
        action: ramp,
      )!;
      expect(old.cfg, {
        'path': 'downstream/plc/pump',
        'action': 'ramp',
        'on': 'rising',
        'args': {'ramp_s': 30},
      });
      expect(old.pins, isEmpty);
    });
  });

  group('the action block', () {
    final b = FlowBlock(
      id: 'ramp1',
      type: bt('invoke'),
      cfg: <String, Object?>{
        'path': 'downstream/plc/pump',
        'action': 'ramp',
        'args': {'target': 40},
      }.lock,
    );

    test('its fields come in groups: target, arguments, behaviour, events, '
        'state', () {
      final t = types['invoke'];
      final fields = fieldsOf(t, b);
      expect(
        [for (final f in fields) '${groupOf(t, b, f).name}:${f.name}'],
        [
          'target:path',
          'target:action',
          'arguments:target',
          'behaviour:trigger',
          'behaviour:in',
          'behaviour:auto_run',
          'behaviour:interval_ms',
          'behaviour:enabled',
          'behaviour:run_on_start',
          'behaviour:on',
          'behaviour:allow_bad',
          'events:sent',
          'events:ok',
          'events:error',
          'state:out',
          'state:result',
          'state:running',
          'state:last_run',
        ],
      );
      String label(String id) => fields.firstWhere((f) => f.id.key == id).label;
      expect(label('in:trigger'), 'Trigger');
      expect(label('p:interval_ms'), 'Every');
      expect(label('p:auto_run'), 'Auto run');
      expect(label('p:run_on_start'), 'Run on start');
      expect(label('out:last_run'), 'Last run');
      expect(label('out:result'), 'Result');
      expect(label('out:out'), 'Output');
      // `run_on_start` has no port; its warning is the catalog's.
      final ros = fields.firstWhere((f) => f.id.key == 'p:run_on_start');
      expect(ros.inPort, isNull);
      expect(ros.spec!.description, startsWith('WARNING:'));
    });

    test('a behaviour that is set shows on the block', () {
      final every = b.copyWith(cfg: b.cfg.add('interval_ms', 5000));
      expect(
        [for (final f in rowsOf(types['invoke'], every)) f.id.key],
        [
          'arg:target',
          'in:trigger',
          'p:interval_ms',
          'out:ok',
          'out:error',
        ],
      );
    });

    test('set, load_value and list_children have the same groups where '
        'they have the fields', () {
      final set = FlowBlock(
        id: 's',
        type: bt('set'),
        cfg: <String, Object?>{'path': 'downstream/plc/fan'}.lock,
      );
      expect([for (final f in rowsOf(types['set'], set)) f.id.key], ['in:in']);
      expect(
        {
          for (final f in fieldsOf(types['set'], set))
            groupOf(types['set'], set, f),
        },
        {
          FieldGroup.target,
          FieldGroup.behaviour,
          FieldGroup.events,
          FieldGroup.state,
        },
      );
      final load = FlowBlock(id: 'l', type: bt('load_value'));
      expect(
        [for (final f in rowsOf(types['load_value'], load)) f.id.key],
        [
          'p:key',
          'in:trigger',
          'out:error',
          'out:out',
        ],
      );
      final list = FlowBlock(id: 'c', type: bt('list_children'));
      final path = fieldsOf(
        types['list_children'],
        list,
      ).firstWhere((f) => f.id.key == 'p:path');
      expect(path.label, 'Node');
      expect(
        scopedKeyOf(types['list_children']),
        const ScopedKey(key: 'path', scope: 'path_scope', port: 'in.path'),
      );
      // A type without behaviours has no groups.
      final add = FlowBlock(id: 'x', type: bt('add'));
      expect(
        {
          for (final f in fieldsOf(types['add'], add))
            groupOf(types['add'], add, f),
        },
        {FieldGroup.none},
      );
    });

    test('an event reads when it fired, an error its code and message', () {
      final at = DateTime(2026, 11, 9, 14, 3, 27);
      expect(
        eventText(LiveValue(time: at, value: {'event': 'ok', 'id': 4})),
        '14:03:27',
      );
      expect(
        eventText(
          LiveValue(
            time: at,
            value: {
              'event': 'error',
              'id': 5,
              'code': 'busy',
              'message': 'queue full',
            },
          ),
        ),
        '14:03:27 · busy: queue full',
      );
      expect(eventText(LiveValue(time: at)), isNull);
      expect(eventText(null), isNull);
      expect(lastRunText(0), isNull);
      expect(lastRunText(at.microsecondsSinceEpoch), '14:03:27');
    });

    test('the new blocks read as words', () {
      expect(blockLabel(bt('load_value')), 'Load value');
      expect(blockLabel(bt('list_children')), 'List children');
      expect(blockLabel(bt('rising_edge')), 'Rising edge');
      expect(blockLabel(bt('make_object')), 'Make object');
      expect(blockLabel(bt('sample_and_hold')), 'Sample and hold');
      expect(blockLabel(bt('wasm')), 'WASM');
      expect(blockLabel(bt('block:mean')), 'mean');
      String out(String type, String port) => fieldsOf(
        types[type],
        FlowBlock(id: 'x', type: bt(type)),
      ).firstWhere((f) => f.id.key == 'out:$port').label;
      expect(out('rising_edge', 'on_edge'), 'On edge');
      expect(out('stats', 'avg'), 'Average');
      expect(
        fieldsOf(
          types['debounce'],
          FlowBlock(id: 'x', type: bt('debounce')),
        ).firstWhere((f) => f.id.key == 'p:ms').label,
        'Quiet time (ms)',
      );
      // Named inputs keep the names the user gave them.
      expect(
        [
          for (final f in rowsOf(
            types['make_object'],
            FlowBlock(id: 'x', type: bt('make_object')),
          ))
            f.label,
        ],
        ['a', 'b', 'Output'],
      );
    });
  });

  group('custom blocks, pure', () {
    const spec = CustomBlockSpec(
      name: 'mean2',
      description: 'The mean of two values',
      inputs: ['first', 'second'],
      outputs: ['out'],
      defaults: {'second': 0},
    );

    test('a selection becomes a block and one instance; the wires that '
        'crossed its edge end at the instance', () {
      final d = draft();
      final (next, id) = createCustomBlock(d, {'sum', 'half'}, spec)!;
      expect(id, 'mean21');
      expect(next.blocks.keys, isNot(contains('sum')));
      expect(next.blocks[id]!.type.wire, 'block:mean2');
      expect(next.blocks[id]!.x, 300);
      expect(
        [
          for (final e in next.edges)
            '${e.from}.${e.fromPort}>${e.to}.${e.toPort}',
        ],
        [
          'name.out>path.in.1',
          'a.out>mean21.first',
          'b.out>mean21.second',
          'mean21.out>mean.in',
        ],
      );
      final def = defJson(next, 'mean2');
      expect(def['description'], 'The mean of two values');
      expect(def['inputs'], [
        {
          'name': 'first',
          'to': ['sum.in.0'],
        },
        {
          'name': 'second',
          'to': ['sum.in.1'],
          'default': 0,
        },
      ]);
      expect(def['outputs'], [
        {'name': 'out', 'from': 'half.out'},
      ]);
      expect((def['nodes']! as Map).keys, ['sum', 'half']);
      expect((def['nodes']! as Map)['half'], {
        'type': 'divide',
        'values': {'in.1': 2},
      });
      expect(def['edges'], [
        ['sum.out', 'half.in.0'],
      ]);
      // The definition goes out with the flow's.
      expect((defMap(next)['blocks']! as Map).keys, ['mean2']);
      expect((defMap(next)['nodes']! as Map)[id], {'type': 'block:mean2'});
      expect(instancesOf(next, 'mean2'), 1);
      // The instance draws its declared ports, under their own names.
      expect(rowIds(next, id), ['in:first', 'in:second', 'out:out']);
      final t = customTypeOf('mean2', blockDefsOf(next)['mean2']!);
      final first = fieldsOf(t, next.blocks[id]!).first;
      expect(
        (first.label, first.inPort, first.outPort, first.operand),
        (
          'first',
          'first',
          'first',
          true,
        ),
      );
      expect(instanceValueOf(next, next.blocks[id]!, 'second').raw, 0);
      expect(
        instanceEnd(next, next.blocks[id]!, 'first', output: false),
        PortEnd('mean21/sum', 'in.0'),
      );
      expect(
        instanceEnd(next, next.blocks[id]!, 'out', output: true),
        PortEnd('mean21/half', 'out'),
      );
    });

    test('a name must be free and well formed', () {
      final d = draft();
      BlockNameProblem? bad(CustomBlockSpec s) => customBlockProblem(d, s);
      expect(bad(spec), isNull);
      expect(
        bad(const CustomBlockSpec(name: 'my block')),
        BlockNameProblem.name,
      );
      expect(
        bad(const CustomBlockSpec(name: 'm', inputs: ['a b'])),
        BlockNameProblem.port,
      );
      expect(
        bad(const CustomBlockSpec(name: 'm', inputs: ['x'], outputs: ['x'])),
        BlockNameProblem.duplicate,
      );
      final (next, _) = createCustomBlock(d, {'sum', 'half'}, spec)!;
      expect(customBlockProblem(next, spec), BlockNameProblem.taken);
    });

    test('the inside is a draft with an inputs block and an outputs block; '
        'what is done there is the definition again', () {
      final (flow, id) = createCustomBlock(draft(), {'sum', 'half'}, spec)!;
      final inner = insideDraftOf(flow, 'mean2')!;
      expect(inner.blocks.keys, ['sum', 'half', blockInputsId, blockOutputsId]);
      expect(boundaryOf(inner).inputs, ['first', 'second']);
      expect(boundaryOf(inner).outputs, ['out']);
      expect(
        [
          for (final e in inner.edges)
            '${e.from}.${e.fromPort}>${e.to}.${e.toPort}',
        ],
        [
          'sum.out>half.in.0',
          '~in.first>sum.in.0',
          '~in.second>sum.in.1',
          'half.out>~out.out',
        ],
      );
      expect(rowIds(inner, blockInputsId), ['out:first', 'out:second']);
      expect(rowIds(inner, blockOutputsId), ['in:out']);
      // Unchanged, it folds back to the same definition.
      expect(
        Value.from(defJson(foldInside(flow, 'mean2', inner), 'mean2')),
        Value.from(defJson(flow, 'mean2')),
      );
      // A third input, wired to the divisor; the output `out` taken away.
      var edited = resizeBoundary(inner, input: true, add: true)!;
      expect(boundaryOf(edited).inputs, ['first', 'second', 'in1']);
      edited = edited.copyWith(
        edges: edited.edges.add(
          const FlowEdge(
            from: blockInputsId,
            fromPort: 'in1',
            to: 'half',
            toPort: 'in.1',
          ),
        ),
      );
      edited = resizeBoundary(edited, input: false, add: false)!;
      final folded = foldInside(flow, 'mean2', edited);
      final def = blockDefsOf(folded)['mean2']!;
      expect(
        [for (final p in def.inputs) p.name],
        [
          'first',
          'second',
          'in1',
        ],
      );
      expect(def.inputs.last.ends, [PortEnd('half', 'in.1')]);
      expect(def.outputs, isEmpty);
      // The instance lost the wire of the output that is gone.
      expect(folded.edges.where((e) => e.from == id), isEmpty);
      expect(folded.edges.where((e) => e.to == id).length, 2);
    });

    test('rename follows every instance; delete only when none is left', () {
      final (flow, id) = createCustomBlock(draft(), {'sum', 'half'}, spec)!;
      final renamed = renameBlock(flow, 'mean2', 'average')!;
      expect(blockDefsOf(renamed).keys, ['average']);
      expect(renamed.blocks[id]!.type.wire, 'block:average');
      expect(renameBlock(flow, 'mean2', 'not ok'), isNull);
      expect(removeBlock(flow, 'mean2'), isNull, reason: 'in use');
      final unused = withoutBlocks(flow, {id});
      expect(blockDefsOf(removeBlock(unused, 'mean2')), isEmpty);
      expect(
        defMap(removeBlock(unused, 'mean2')!).containsKey('blocks'),
        isFalse,
      );
    });

    test('a library block is copied with the blocks it uses, at its '
        'version; the flow keeps a block it already has', () {
      final d = withLibraryBlock(
        draft(),
        'scaled',
        blockDef(libScaled),
        version: 3,
        requires: {'mean': blockDef(libMean)},
      );
      expect(blockDefsOf(d).keys, ['mean', 'scaled']);
      expect(blockDefsOf(d)['scaled']!.libraryVersion, 3);
      expect(blockDefsOf(d)['mean']!.libraryVersion, isNull);
      expect(blockClosure(blockDefsOf(d), ['scaled']), ['mean', 'scaled']);
      // Copied again: nothing changes without `replace`.
      final own = blockDef({...libScaled, 'description': 'mine'});
      final kept = withLibraryBlock(
        withBlockDefs(d, {...blockDefsOf(d), 'scaled': own}),
        'scaled',
        blockDef(libScaled),
        version: 4,
      );
      expect(blockDefsOf(kept)['scaled']!.description, 'mine');
      final updated = withLibraryBlock(
        kept,
        'scaled',
        blockDef(libScaled),
        version: 4,
        replace: true,
      );
      expect(blockDefsOf(updated)['scaled']!.libraryVersion, 4);
      // The library gets the definition without the editor's mark: as it
      // came, so with no `layout`, which it never had.
      expect(
        libraryDefJsonOf(blockDefsOf(updated)['scaled']!).containsKey('layout'),
        isFalse,
      );
      expect(
        sameBlockDef(blockDefsOf(updated)['scaled']!, blockDef(libScaled)),
        isTrue,
      );
      expect(
        sameBlockDef(blockDefsOf(updated)['scaled']!, blockDef(libMean)),
        isFalse,
      );
    });

    test('the clipboard carries the definitions of the instances it holds', () {
      final (flow, id) = createCustomBlock(draft(), {'sum', 'half'}, spec)!;
      final text = clipTextOf(flow, {id, 'mean'})!;
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['format'], clipFormat);
      expect((json['blocks']! as Map).keys, ['mean2']);
      // A copy without instances has no `blocks`.
      expect(
        (jsonDecode(clipTextOf(flow, {'name'})!) as Map).containsKey('blocks'),
        isFalse,
      );
      // Into another flow: the definition comes along.
      final (pasted, ids) = pasteClip(
        const FlowDraft(id: 'other'),
        clipped(text),
        100,
        100,
      );
      expect(ids, ['mean', id]);
      expect(blockDefsOf(pasted).keys, ['mean2']);
      expect(pasted.edges.single.from, id);
      // Where the flow has a block of that name, its own stays.
      final mine = blockDef({'description': 'mine'});
      final own = withBlockDefs(const FlowDraft(id: 'other'), {'mean2': mine});
      expect(
        blockDefsOf(pasteClip(own, clipped(text), 0, 0).$1)['mean2'],
        mine,
      );
    });
  });

  group('the editor', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    FlowDraft now() => s.state.flowEditor.draft!;
    SelectFlowEditor ed() => SelectFlowEditor(s.state);

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
          Value.from(catalog0226()),
        ]
        ..invokes['wy/central/dataflows/line ▸ history'] = [
          Value.from([line]),
        ]
        ..invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': true}),
        ]
        ..invokes['wy/central/dataflows ▸ deploy'] = [const VNull()]
        ..invokes['wy/central/dataflows ▸ list_blocks'] = [
          Value.from([
            {
              'name': 'mean',
              'version': 2,
              'description': 'The mean of two values',
              'inputs': ['a', 'b', 'n'],
              'outputs': ['out'],
            },
            {
              'name': 'scaled',
              'version': 3,
              'inputs': ['x'],
              'outputs': ['out'],
            },
          ]),
        ]
        ..invokes['wy/central/dataflows ▸ get_block'] = [
          Value.from({
            'name': 'scaled',
            'version': 3,
            'def': libScaled,
            'requires': {'mean': libMean},
          }),
        ];
      await s.dispatchAndWait(LoadFlowAction('line'));
      await s.dispatchAndWait(RetrieveBlockLibraryAction());
    });

    test('binding into a key asks for the scope; the scope is written, and '
        'unbinding keeps it', () async {
      expect(ed().scopePrompt, isNull);
      s.dispatchSync(ConnectPortsAction('path', 'out', 'level', 'in.key'));
      expect(ed().scopePrompt, 'level');
      expect(
        scopeSuggestion(now().blocks['level']!.cfg['key'] as String?),
        'downstream/modbus/line1/**',
      );
      s
        ..dispatchSync(
          SetBlockParamAction(
            'level',
            'key_scope',
            'downstream/modbus/line1/**',
          ),
        )
        ..dispatchSync(SetScopePromptAction(null));
      await s.dispatchAndWait(DeployFlowAction());
      final sent = api.calls.lastWhere((c) => c.action == 'deploy').args!;
      final def = toDart(sent['def'])! as Map<String, Object?>;
      expect((def['nodes']! as Map)['level'], {
        'type': 'subscribe',
        'key': 'downstream/modbus/line1/level',
        'key_scope': 'downstream/modbus/line1/**',
      });
      expect(def['edges'], contains(equals(['path.out', 'level.in.key'])));

      // Unbound: the last key stays as the typed one, and so does the scope.
      s.dispatchSync(
        DisconnectEdgeAction(
          'level',
          'in.key',
          param: 'key',
          keep: 'downstream/modbus/line1/pump1',
        ),
      );
      expect(now().blocks['level']!.cfg.unlock, {
        'key': 'downstream/modbus/line1/pump1',
        'key_scope': 'downstream/modbus/line1/**',
      });
      // Bound again: the block has its scope, nothing is asked.
      s.dispatchSync(ConnectPortsAction('path', 'out', 'level', 'in.key'));
      expect(ed().scopePrompt, isNull);
      expect(rowIds(now(), 'level'), contains('p:key_scope'));
    });

    test('a point dropped on a key field wires a subscribe into it and asks '
        'for the scope too', () {
      s.dispatchSync(
        AddBlockAction(
          bt('subscribe'),
          40,
          600,
          cfg: {'key': 'storage/names/current'},
          into: PortEnd('level', 'in.key'),
        ),
      );
      expect(ed().scopePrompt, 'level');
      expect(now().edges.last.toPort, 'in.key');
    });

    test('an action block: its definition, a bound argument, behaviours, '
        'and the trigger call', () async {
      const caps = FlowCaps(scopes: true, trigger: true, args: true);
      final e = blockOfEntry(
        const ActionPick('wy/central/downstream/plc/pump', 'ramp'),
        action: ActionInfo(
          name: 'ramp',
          level: Perm.write,
          params: [
            const ParamSpec(
              name: 'target',
              type: TypeCode.number,
              required: true,
            ),
            const ParamSpec(
              name: 'ramp_s',
              type: TypeCode.number,
              defaultValue: 30,
            ),
          ].lock,
        ),
        caps: caps,
      )!;
      s.dispatchSync(
        AddBlockAction(e.type.type, 600, 600, cfg: e.cfg, pins: e.pins),
      );
      expect(now().blocks.keys.last, 'invoke1');
      expect(rowIds(now(), 'invoke1'), [
        'arg:target',
        'in:trigger',
        'out:ok',
        'out:error',
      ]);
      // An argument's value from another block; a behaviour; an event out.
      s
        ..dispatchSync(
          ConnectPortsAction('half', 'out', 'invoke1', 'arg.target'),
        )
        ..dispatchSync(SetBlockParamAction('invoke1', 'interval_ms', 60000))
        ..dispatchSync(SetBlockParamAction('invoke1', 'run_on_start', true))
        ..dispatchSync(ConnectPortsAction('invoke1', 'error', 'mean', 'in'));
      expect(ed().scopePrompt, isNull, reason: 'no key was bound');
      await s.dispatchAndWait(DeployFlowAction());
      final sent = api.calls.lastWhere((c) => c.action == 'deploy').args!;
      final def = toDart(sent['def'])! as Map<String, Object?>;
      expect((def['nodes']! as Map)['invoke1'], {
        'type': 'invoke',
        // The defaults of choice parameters are written, as for every block.
        'on': 'any',
        'path': 'downstream/plc/pump',
        'action': 'ramp',
        'args': {'target': null, 'ramp_s': 30},
        'interval_ms': 60000,
        'run_on_start': true,
      });
      expect(
        def['edges'],
        contains(equals(['half.out', 'invoke1.arg.target'])),
      );
      expect(def['edges'], contains(equals(['invoke1.error', 'mean.in'])));
      expect(def['permissions'], {'maxperm': 'write'});
      expect((def['layout']! as Map)['invoke1~pin~arg:ramp_s'], [0, 0]);

      // Read back, it is the same block.
      api.invokes['wy/central/dataflows/line ▸ history'] = [
        Value.from([def]),
      ];
      await s.dispatchAndWait(LoadFlowAction('line'));
      expect(rowIds(now(), 'invoke1'), [
        'arg:target',
        'in:trigger',
        'p:interval_ms',
        'p:run_on_start',
        'out:ok',
        'out:error',
      ]);

      // Run: the engine's trigger action on the deployed flow.
      api.invokes['wy/central/dataflows/line ▸ trigger'] = [const VNull()];
      final ok = await s.dispatchAndWait(TriggerBlockAction('invoke1'));
      expect(ok.isCompletedOk, isTrue);
      final call = api.calls.last;
      expect((call.key, call.action), ('wy/central/dataflows/line', 'trigger'));
      expect(toDart(call.args), {'node': 'invoke1'});
    });

    test('a refused trigger says why', () async {
      Future<StudioError?> refused(Status st, [String m = '']) async {
        api.errors['wy/central/dataflows/line ▸ trigger'] = WyrmException.of(
          st,
          m,
        );
        final r = await s.dispatchAndWait(TriggerBlockAction('invoke1'));
        return switch (r.originalError) {
          final StudioException e => e.error,
          _ => null,
        };
      }

      // No words from the broker: Studio names why (the app says it).
      final denied = await refused(Status.permissionDenied);
      expect((denied?.message, denied?.hint), ('', ErrorHint.runDenied));
      expect(
        (await refused(Status.notSupported))?.hint,
        ErrorHint.runNotRunning,
      );
      expect((await refused(Status.notFound))?.hint, ErrorHint.runNoTrigger);
      // The broker's words as they came, and no hint of Studio's.
      final own = await refused(
        Status.invalidParameter,
        'node level cannot be triggered',
      );
      expect(
        (own?.message, own?.hint),
        ('node level cannot be triggered', null),
      );
      expect((await refused(Status.busy, 'queue full'))?.message, 'queue full');
    });

    test('create a custom block, open its inside, change it, come back: '
        'one step each, and the flow validates as a whole', () async {
      s.dispatchSync(
        CreateCustomBlockAction(
          {'sum', 'half'},
          const CustomBlockSpec(
            name: 'mean2',
            inputs: ['first', 'second'],
            outputs: ['out'],
          ),
        ),
      );
      expect(ed().selection.unlock, {'mean21'});
      expect(ed().undo.length, 1);
      // A second instance, a constant on its input.
      s
        ..dispatchSync(AddBlockAction(bt('block:mean2'), 300, 600))
        ..dispatchSync(SetOperandValueAction('mean22', 'second', 7));
      expect(now().blocks['mean22']!.cfg.unlock, {
        'values': {'second': 7},
      });
      expect(instancesOf(now(), 'mean2'), 2);

      s.dispatchSync(EnterBlockAction('mean2', instance: 'mean21'));
      expect(ed().frames.single.block, 'mean2');
      expect(insidePath(ed().frames), 'mean21');
      expect(now().blocks.keys, contains(blockInputsId));
      expect(ed().undo, isEmpty, reason: 'the inside has its own history');
      // The canvas shows the inside; the flow is still the whole flow.
      expect(ed().root!.blocks.keys, contains('mean21'));
      expect(ed().allTypes.map((t) => t.type), contains(BoundaryType.inputs));

      // Inside: the boundary blocks stay; the divisor changes.
      s
        ..dispatchSync(
          RemoveBlocksAction(const [blockInputsId, blockOutputsId]),
        )
        ..dispatchSync(SetOperandValueAction('half', 'in.1', 4));
      expect(now().blocks.keys, contains(blockInputsId));
      await s.dispatchAndWait(ValidateFlowAction());
      final checked = api.calls.lastWhere((c) => c.action == 'validate').args!;
      final def = toDart(checked['def'])! as Map<String, Object?>;
      expect((def['nodes']! as Map).keys, contains('mean21'));
      expect(
        (((def['blocks']! as Map)['mean2']! as Map)['nodes']! as Map)['half'],
        {
          'type': 'divide',
          'values': {'in.1': 4},
        },
      );
      // Deploy waits for the flow itself.
      final before = api.calls.where((c) => c.action == 'deploy').length;
      await s.dispatchAndWait(DeployFlowAction());
      expect(api.calls.where((c) => c.action == 'deploy').length, before);

      // The inputs block grows by one; the last one goes with −.
      s.dispatchSync(ResizeBlockPortsAction(input: true, add: true));
      expect(boundaryOf(now()).inputs, ['first', 'second', 'in1']);
      s
        ..dispatchSync(ResizeBlockPortsAction(input: true, add: false))
        ..dispatchSync(LeaveBlockAction());
      expect(ed().frames, isEmpty);
      expect(now().blocks.keys, containsAll(['mean21', 'mean22']));
      expect(
        ((defJson(now(), 'mean2')['nodes']! as Map)['half']! as Map)['values'],
        {'in.1': 4},
      );
      expect(ed().undo.length, 4, reason: 'create, add, set, edit inside');
      s.dispatchSync(UndoFlowAction());
      expect(
        ((defJson(now(), 'mean2')['nodes']! as Map)['half']! as Map)['values'],
        {'in.1': 2},
      );

      // Opened and left without a change: no step.
      s
        ..dispatchSync(EnterBlockAction('mean2'))
        ..dispatchSync(LeaveBlockAction());
      expect(ed().undo.length, 3);
      expect(insidePath(ed().frames), '');
    });

    test('rename and delete go through the flow', () {
      s
        ..dispatchSync(
          CreateCustomBlockAction(
            {'sum', 'half'},
            const CustomBlockSpec(
              name: 'mean2',
              inputs: ['a', 'b'],
              outputs: ['out'],
            ),
          ),
        )
        ..dispatchSync(RenameCustomBlockAction('mean2', 'average'));
      expect(now().blocks['mean21']!.type.wire, 'block:average');
      s.dispatchSync(RemoveCustomBlockAction('average'));
      expect(blockDefsOf(now()).keys, ['average'], reason: 'in use');
      s
        ..dispatchSync(RemoveBlocksAction(const ['mean21']))
        ..dispatchSync(RemoveCustomBlockAction('average'));
      expect(blockDefsOf(now()), isEmpty);
    });

    test('two reads of the library, the first answered last: the newer '
        'library stays', () async {
      Value lib(String name) => Value.from([
        {
          'name': name,
          'version': 1,
          'inputs': ['x'],
          'outputs': ['out'],
        },
      ]);
      api.invokesInTurn['wy/central/dataflows ▸ list_blocks'] = [
        (const Duration(milliseconds: 60), [lib('older')]),
        (const Duration(milliseconds: 5), [lib('newer')]),
      ];
      await Future.wait([
        s.dispatchAndWait(RetrieveBlockLibraryAction()),
        s.dispatchAndWait(RetrieveBlockLibraryAction()),
      ]);
      expect([for (final b in ed().library) b.name], ['newer']);
    });

    test('a library block whose answer comes after its flow was left is '
        'not placed there', () async {
      final get = api.invokes['wy/central/dataflows ▸ get_block']!;
      api
        ..invokesInTurn['wy/central/dataflows ▸ get_block'] = [
          (const Duration(milliseconds: 60), get),
        ]
        ..invokes['wy/central/dataflows/other ▸ history'] = [
          Value.from([
            {...line, 'id': 'other'},
          ]),
        ];
      final placed = s.dispatchAndWait(
        PlaceLibraryBlockAction('scaled', 300, 600),
      );
      await s.dispatchAndWait(LoadFlowAction('other'));
      await placed;
      expect(s.state.flowEditor.flowId, 'other');
      expect(blockDefsOf(now()), isEmpty);
      expect(now().blocks.keys, isNot(contains('scaled1')));
    });

    test('two reads of the flows, the first answered last: the newer '
        'table stays', () async {
      final nodes = (line['nodes']! as Map).cast<String, Object?>();
      final more = {
        ...line,
        'nodes': {
          ...nodes,
          'extra': {'type': 'add'},
        },
      };
      api
        ..children_['wy/central/dataflows'] = [Child('line', NodeMeta())]
        ..invokesInTurn['wy/central/dataflows/line ▸ history'] = [
          (
            const Duration(milliseconds: 300),
            [
              Value.from([line]),
            ],
          ),
          (
            const Duration(milliseconds: 5),
            [
              Value.from([more]),
            ],
          ),
        ];
      await Future.wait([
        s.dispatchAndWait(RetrieveFlowsAction()),
        s.dispatchAndWait(RetrieveFlowsAction()),
      ]);
      expect(s.state.flows.table['line']!.blocks, nodes.length + 1);
    });

    test('one flow opened, then another before the first answered: the '
        'one opened last stays', () async {
      api
        ..invokesInTurn['wy/central/dataflows/line ▸ history'] = [
          (
            const Duration(milliseconds: 60),
            [
              Value.from([line]),
            ],
          ),
        ]
        ..invokes['wy/central/dataflows/other ▸ history'] = [
          Value.from([
            {...line, 'id': 'other'},
          ]),
        ];
      await Future.wait([
        s.dispatchAndWait(LoadFlowAction('line')),
        s.dispatchAndWait(LoadFlowAction('other')),
      ]);
      expect(s.state.flowEditor.flowId, 'other');
      expect(now().id, 'other');
    });

    test('a check answered after the flow changed is dropped: the newer '
        'check stands', () async {
      Value ok(bool ok) => Value.from(
        ok ? {'ok': true} : {'ok': false, 'error': 'node path: bad'},
      );
      api.invokesInTurn['wy/central/dataflows ▸ validate'] = [
        (const Duration(milliseconds: 600), [ok(false)]),
        (const Duration(milliseconds: 5), [ok(true)]),
      ];
      int checks() => api.calls.where((c) => c.action == 'validate').length;
      final sent = checks();
      final first = s.dispatchAndWait(ValidateFlowAction());
      // the first check is sent (after its 400 ms pause) and waits
      for (var i = 0; i < 300 && checks() == sent; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(checks(), sent + 1);
      s.dispatchSync(RemoveBlocksAction(const ['path']));
      final second = s.dispatchAndWait(ValidateFlowAction());
      await Future.wait([first, second]);
      expect(ed().problems, isEmpty);
    });

    test('the library: listed, a block placed is copied with what it '
        'uses, saved back with its blocks first', () async {
      expect(ed().caps.blocks, isTrue);
      expect(
        [for (final b in ed().library) '${b.name} v${b.version}'],
        [
          'mean v2',
          'scaled v3',
        ],
      );
      await s.dispatchAndWait(PlaceLibraryBlockAction('scaled', 300, 600));
      expect(toDart(api.calls.lastWhere((c) => c.action == 'get_block').args), {
        'name': 'scaled',
      });
      expect(blockDefsOf(now()).keys, ['mean', 'scaled']);
      expect(now().blocks['scaled1']!.type.wire, 'block:scaled');
      expect(blockDefsOf(now())['scaled']!.libraryVersion, 3);
      expect(
        ed().undo.length,
        1,
        reason: 'the copy and the instance: one step',
      );
      expect(rowIds(now(), 'scaled1'), ['in:x', 'out:out']);

      // A newer version in the library: update replaces the copy.
      api.invokes['wy/central/dataflows ▸ get_block'] = [
        Value.from({
          'name': 'scaled',
          'version': 5,
          'def': {
            ...libScaled,
            'outputs': <Object>[],
          },
          'requires': {'mean': libMean},
        }),
      ];
      s.dispatchSync(ConnectPortsAction('scaled1', 'out', 'mean', 'in'));
      await s.dispatchAndWait(UpdateBlockFromLibraryAction('scaled'));
      expect(blockDefsOf(now())['scaled']!.libraryVersion, 5);
      expect(
        now().edges.where((e) => e.from == 'scaled1'),
        isEmpty,
        reason: 'the output is gone, and its wire',
      );

      // Save a block made here that uses `mean` (held) and `helper` (not).
      api.invokes['wy/central/dataflows ▸ put_block'] = [
        Value.from({'name': 'x', 'version': 9}),
      ];
      final withOwn = withBlockDefs(now(), {
        ...blockDefsOf(now()),
        'helper': blockDef({
          'inputs': <Object>[],
          'outputs': <Object>[],
          'nodes': {
            'm': {'type': 'block:mean'},
          },
          'edges': <Object>[],
        }),
        'top': blockDef({
          'inputs': <Object>[],
          'outputs': <Object>[],
          'nodes': {
            'h': {'type': 'block:helper'},
          },
          'edges': <Object>[],
        }),
      });
      s.dispatchSync(PasteBlocksAction(null, 0, 0));
      await s.dispatchAndWait(_SetDraft(withOwn));
      await s.dispatchAndWait(SaveBlockToLibraryAction('top'));
      final puts = [
        for (final c in api.calls)
          if (c.action == 'put_block') str(c.args!['name']),
      ];
      expect(puts, ['helper', 'top'], reason: 'mean is in the library');
      expect(blockDefsOf(now())['top']!.libraryVersion, 9);
      final put = api.calls.lastWhere((c) => c.action == 'put_block').args!;
      expect(
        (toDart(put['def'])! as Map).keys,
        containsAll(['inputs', 'outputs', 'nodes', 'edges']),
      );
    });

    test('a broker without the library: custom blocks are off, nothing '
        'breaks', () async {
      api.invokes.remove('wy/central/dataflows ▸ list_blocks');
      final r = await s.dispatchAndWait(RetrieveBlockLibraryAction());
      expect(r.isCompletedOk, isTrue);
      expect(
        ed().libraryOff,
        LibraryOff.refused(StatusCode.of(Status.notFound)),
      );
      expect(ed().library, isEmpty);
      expect(ed().caps.blocks, isFalse);
      // The same flow read again keeps the answer.
      await s.dispatchAndWait(LoadFlowAction('line'));
      expect(ed().caps.blocks, isFalse);
    });
  });
}

/// Puts a draft in the editor (a test's shortcut for many edits).
class _SetDraft extends ReduxAction<AppState> {
  _SetDraft(this.draft);

  final FlowDraft draft;

  @override
  AppState reduce() => state.copyWith.flowEditor(draft: draft);
}
