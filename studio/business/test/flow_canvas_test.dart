import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/add_block_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/move_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/paste_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/redo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/select_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_clipboard_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/set_operand_value_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/undo_flow_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

// The canvas tools of the flow editor (flow-editor.md §12–§15, owner
// decisions 2026-11-09): pins, selection and clipboard, undo, the cut of a
// selection into a sub-graph, and what the value viewer saves.

/// A catalog with a field that is off the block by default: `window.fn`
/// has no port, no default and is not required.
final List<Map<String, Object>> catalog = [
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
    'type': 'window',
    'category': 'Time',
    'inputs': ['in', 'in.size_s'],
    'outputs': ['out'],
    'params': [
      {'name': 'size_s', 'type': 'number', 'default': 60, 'port': 'in.size_s'},
      {
        'name': 'fn',
        'type': 'string',
        'choices': ['avg', 'min', 'max'],
      },
      {'name': 'meta', 'type': 'map'},
    ],
  },
  {
    'type': 'concat',
    'category': 'String',
    'inputs': <String>[],
    'outputs': ['out'],
    'values': true,
    'dyn_inputs': {
      'param': 'inputs',
      'prefix': 'in.',
      'default': ['0', '1'],
    },
    'params': [
      {'name': 'inputs', 'type': 'array'},
      {'name': 'strict', 'type': 'bool', 'default': false},
    ],
  },
  {
    'type': 'publish',
    'category': 'Sinks',
    'inputs': ['in'],
    'outputs': <String>[],
    'params': [
      {'name': 'node', 'type': 'string', 'required': true},
    ],
  },
];

final Map<String, NodeType> types = {
  for (final t in catalog) t['type']! as String: nodeTypeOf(Value.from(t)),
};

/// `level → avg → text → out`, and `avg` also feeds `out2`.
final Map<String, Object> tank = {
  'id': 'tank',
  'version': 3,
  'nodes': {
    'level': {'type': 'subscribe', 'key': 'downstream/plc/level'},
    'avg': {'type': 'window', 'size_s': 30},
    'text': {
      'type': 'concat',
      'values': {'in.0': 'L='},
    },
    'out': {'type': 'publish', 'node': 'text'},
    'out2': {'type': 'publish', 'node': 'avg'},
  },
  'edges': [
    ['level.out', 'avg.in'],
    ['avg.out', 'text.in.1'],
    ['text.out', 'out.in'],
    ['avg.out', 'out2.in'],
  ],
  'layout': {
    'level': [40, 40],
    'avg': [300, 40],
    'text': [560, 40],
    'out': [820, 40],
    'out2': [820, 200],
  },
};

FlowDraft draft() => flowDraftOf('tank', Value.from(tank));

List<String> rowIds(FlowDraft d, String id) => [
  for (final f in rowsOf(
    types[d.blocks[id]!.type],
    d.blocks[id]!,
    edges: d.edges,
  ))
    f.id,
];

FlowField field(FlowDraft d, String block, String id) => fieldsOf(
  types[d.blocks[block]!.type],
  d.blocks[block]!,
  edges: d.edges,
).firstWhere((f) => f.id == id);

void main() {
  group('pins', () {
    test('a flow without pin data draws the defaults of each type', () {
      final d = draft();
      expect(d.blocks['avg']!.pins, isEmpty);
      // `fn` and `meta` are off the block; `size_s` has a port and a value.
      expect(rowIds(d, 'avg'), ['in:in', 'p:size_s', 'out:out']);
    });

    test('a field is pinned and taken off per block; a choice equal to the '
        'default is not kept', () {
      final d = draft();
      final avg = d.blocks['avg']!;
      final on = withPin(avg, field(d, 'avg', 'p:fn'), d.edges, pinned: true)!;
      expect(on.pins.unlock, {'p:fn': true});
      final d1 = d.copyWith(blocks: d.blocks.add('avg', on));
      expect(rowIds(d1, 'avg'), ['in:in', 'p:size_s', 'p:fn', 'out:out']);

      final off = withPin(
        on,
        field(d1, 'avg', 'p:size_s'),
        d1.edges,
        pinned: false,
      )!;
      expect(off.pins.unlock, {'p:fn': true, 'p:size_s': false});
      final d2 = d1.copyWith(blocks: d1.blocks.add('avg', off));
      expect(rowIds(d2, 'avg'), ['in:in', 'p:fn', 'out:out']);

      // Back to what the type does by itself: no entry.
      final back = withPin(
        off,
        field(d2, 'avg', 'p:fn'),
        d2.edges,
        pinned: false,
      )!;
      expect(back.pins.unlock, {'p:size_s': false});
      expect(
        withPin(back, field(d2, 'avg', 'p:fn'), d2.edges, pinned: false),
        isNull,
        reason: 'nothing changes',
      );
    });

    test('a bound field is a row and cannot be taken off', () {
      final d = draft();
      final avg = d.blocks['avg']!;
      // `in` has a wire into it, `out` two out of it.
      for (final id in ['in:in', 'out:out']) {
        expect(
          withPin(avg, field(d, 'avg', id), d.edges, pinned: false),
          isNull,
        );
      }
      // Even when the layout says off (an older choice), a wire shows it.
      final hidden = d.copyWith(
        blocks: d.blocks.add(
          'avg',
          avg.copyWith(pins: avg.pins.add('in:in', false)),
        ),
      );
      expect(rowIds(hidden, 'avg'), contains('in:in'));
    });

    test('pins travel in the layout as two numbers and come back', () {
      final d = draft();
      final avg = d.blocks['avg']!;
      final d1 = d.copyWith(
        blocks: d.blocks.add(
          'avg',
          avg.copyWith(
            pins: avg.pins.add('p:fn', true).add('p:size_s', false),
          ),
        ),
      );
      final def = toDart(defOf(d1, 4))! as Map<String, Object?>;
      final layout = def['layout']! as Map<String, Object?>;
      expect(layout['avg'], [300, 40]);
      expect(layout['avg~pin~p:fn'], [1, 0]);
      expect(layout['avg~pin~p:size_s'], [0, 0]);
      // What the engine checks (crates/wyrm-flow/src/def.rs): every value
      // of `layout` is two finite numbers.
      for (final v in layout.values) {
        expect(v, isA<List<Object?>>().having((l) => l.length, 'length', 2));
        expect((v! as List).every((n) => n is num && n.isFinite), isTrue);
      }
      final again = flowDraftOf('tank', defOf(d1, 4));
      expect(again.blocks['avg']!.pins.unlock, {
        'p:fn': true,
        'p:size_s': false,
      });
      expect(again.blocks['avg']!.x, 300);
      expect(again.blocks.keys, d.blocks.keys, reason: 'a pin is no node');
      expect(defOf(again, 4), defOf(d1, 4));
      // The preview runs the definition without its layout: a pin runs
      // nothing again.
      expect(previewDefOf(d1), previewDefOf(d));
      expect(pinKeyOf('avg'), isNull);
      expect(pinKeyOf(pinKey('avg', 'in:in.0')), ('avg', 'in:in.0'));
    });
  });

  group('copy and paste', () {
    test('the text holds the blocks, their pins and the edges among them', () {
      final d = draft();
      final text = clipTextOf(d, {'avg', 'text'})!;
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['format'], 'wyrm-flow-blocks/1');
      expect((json['nodes']! as Map).keys, ['avg', 'text']);
      expect(json['edges'], [
        ['avg.out', 'text.in.1'],
      ], reason: 'edges to level, out and out2 cross the boundary');
      expect(clipTextOf(d, {'nope'}), isNull);
    });

    test('pasted ids are unique, inner edges follow them, the box lands at '
        'the pointer on the grid', () {
      final d = draft();
      final clip = clipOf(clipTextOf(d, {'avg', 'text'}))!;
      final (next, ids) = pasteClip(d, clip, 407, 311);
      expect(ids, ['avg1', 'text1']);
      expect(next.blocks.length, 7);
      expect(next.blocks['avg1']!.cfg['size_s'], 30);
      expect(
        (next.blocks['text1']!.cfg['values']! as Map)['in.0'],
        'L=',
        reason: 'an operand constant comes with its block',
      );
      // avg was at (300, 40), text at (560, 40): the box's corner snaps to
      // (400, 320) and text keeps its 260 px to the right.
      expect((next.blocks['avg1']!.x, next.blocks['avg1']!.y), (400, 320));
      expect((next.blocks['text1']!.x, next.blocks['text1']!.y), (660, 320));
      expect(
        next.edges.sublist(d.edges.length),
        [
          const FlowEdge(
            from: 'avg1',
            fromPort: 'out',
            to: 'text1',
            toPort: 'in.1',
          ),
        ],
      );
      expect(next.edges.take(d.edges.length), d.edges);

      // Again: the next free numbers. Into another flow: ids as they were.
      final (twice, ids2) = pasteClip(next, clip, 0, 0);
      expect(ids2, ['avg2', 'text2']);
      expect(twice.blocks.length, 9);
      final (other, ids3) = pasteClip(const FlowDraft(id: 'b'), clip, 60, 60);
      expect(ids3, ['avg', 'text']);
      expect(other.edges, hasLength(1));
      expect(freeBlockId('tank', {'tank'}.contains), 'tank1');
      expect(freeBlockId('s9', {'s9', 's1'}.contains), 's2');
    });

    test('foreign text is not a clip', () {
      expect(clipOf(null), isNull);
      expect(clipOf(''), isNull);
      expect(clipOf('hello'), isNull);
      expect(clipOf('{"nodes": {"a": {"type": "scale"}}}'), isNull);
      expect(clipOf('{"format": "wyrm-flow-blocks/2", "nodes": {}}'), isNull);
      expect(
        clipOf('{"format": "wyrm-flow-blocks/1", "nodes": {"a": 1}}'),
        isNull,
      );
      expect(clipOf('{"format": "wyrm-flow-blocks/1", "nodes": {}}'), isNull);
      // An edge that names a block the text does not hold is dropped.
      final c = clipOf(
        '{"format": "wyrm-flow-blocks/1", "nodes": {"a": {"type": "x"}}, '
        '"edges": [["z.out", "a.in"]]}',
      )!;
      expect(c.blocks.keys, ['a']);
      expect(c.edges, isEmpty);
    });
  });

  group('a selection as a sub-graph', () {
    test('edges that cross the boundary become inputs and outputs', () {
      final d = draft();
      final s = extractSubflow(d, {'avg', 'text'});
      expect(s.blocks.keys, ['avg', 'text']);
      expect(s.edges.single.to, 'text');
      expect(s.inputs, hasLength(1));
      expect(s.inputs.single.name, 'avg');
      expect(s.inputs.single.outside, [('level', 'out')]);
      expect(s.inputs.single.inside, [('avg', 'in')]);
      // `avg.out` feeds `text` (inside) and `out2` (outside); `text.out`
      // feeds `out`: two outputs, named after their nodes.
      expect([for (final o in s.outputs) o.name], ['text', 'avg']);
      expect(s.outputs[1].inside, [('avg', 'out')]);
      expect(s.outputs[1].outside, [('out2', 'in')]);
    });

    test('one outside source that feeds two inside inputs is one input; '
        'like names get their node in front', () {
      final d = flowDraftOf(
        'x',
        Value.from({
          'nodes': {
            'a': {'type': 'subscribe', 'key': 'k'},
            'b': {'type': 'subscribe', 'key': 'k2'},
            'w1': {'type': 'window'},
            'w2': {'type': 'window'},
            'o': {'type': 'publish', 'node': 'n'},
          },
          'edges': [
            ['a.out', 'w1.in'],
            ['a.out', 'w2.in'],
            ['b.out', 'w1.in.size_s'],
            ['a.out', 'w2.in.size_s'],
            ['w1.size_s', 'o.in'],
          ],
        }),
      );
      final s = extractSubflow(d, {'w1', 'w2'});
      expect(s.edges, isEmpty);
      expect(s.inputs, hasLength(2));
      expect(s.inputs[0].outside, [('a', 'out')]);
      expect(s.inputs[0].inside, [
        ('w1', 'in'),
        ('w2', 'in'),
        ('w2', 'in.size_s'),
      ]);
      expect(s.inputs[0].name, 'w1');
      expect(s.inputs[1].name, 'size_s');
      expect(s.outputs.single.name, 'size_s');
      expect(s.outputs.single.outside, [('o', 'in')]);
      // Nothing selected, everything selected.
      expect(extractSubflow(d, {}).blocks, isEmpty);
      final all = extractSubflow(d, d.blocks.keys.toSet());
      expect(all.inputs, isEmpty);
      expect(all.outputs, isEmpty);
      expect(all.edges, hasLength(5));
    });
  });

  group('typing a value (the inspector and the viewer)', () {
    test('each field says how it is typed, or why not', () {
      final d = draft();
      FieldEdit? edit(String b, String f) =>
          fieldEditOf(d.blocks[b]!, field(d, b, f), d.edges).edit;
      FieldLocked? locked(String b, String f) =>
          fieldEditOf(d.blocks[b]!, field(d, b, f), d.edges).locked;
      expect(edit('avg', 'p:size_s'), FieldEdit.number);
      expect(edit('avg', 'p:fn'), FieldEdit.choice);
      expect(edit('avg', 'p:meta'), FieldEdit.json);
      expect(edit('text', 'p:strict'), FieldEdit.toggle);
      expect(edit('text', 'in:in.0'), FieldEdit.any, reason: 'an operand');
      expect(edit('out', 'p:node'), FieldEdit.text);
      expect(locked('text', 'in:in.1'), FieldLocked.bound);
      expect(locked('avg', 'in:in'), FieldLocked.bound);
      expect(locked('avg', 'out:out'), FieldLocked.output);
      expect(
        fieldEditText(d.blocks['avg']!, field(d, 'avg', 'p:size_s')),
        '30',
      );
      expect(
        fieldEditText(d.blocks['text']!, field(d, 'text', 'in:in.0')),
        'L=',
      );
      expect(fieldEditText(d.blocks['avg']!, field(d, 'avg', 'p:fn')), '');
    });

    test('a text is checked and typed by its kind', () {
      expect(fieldEditError('12.5', FieldEdit.number), isNull);
      expect(fieldEditError('12,5', FieldEdit.number), FieldEditError.number);
      expect(fieldEditError('', FieldEdit.number), isNull);
      expect(fieldEditError('{"a": 1}', FieldEdit.json), isNull);
      expect(fieldEditError('{"a": 1', FieldEdit.json), FieldEditError.json);
      expect(fieldEditError('3', FieldEdit.json), FieldEditError.json);
      expect(fieldEditError('anything', FieldEdit.any), isNull);
      expect(typedText('12.5', FieldEdit.number), 12.5);
      expect(typedText('true', FieldEdit.toggle), true);
      expect(typedText('{"a": [1]}', FieldEdit.json), {
        'a': [1],
      });
      expect(typedText('2', FieldEdit.any), 2);
      expect(typedText('AHU-', FieldEdit.any), 'AHU-');
      expect(typedText('2', FieldEdit.text), '2');
    });
  });

  group('the editor', () {
    late FakeWyrmApi api;
    late Store<AppState> s;

    FlowDraft now() => s.state.flowEditor.draft!;

    setUp(() async {
      final login = FakeLogin();
      api = login.session.api;
      s = fakeStore(login: login);
      await s.dispatchAndWait(SetGatewayAction('http://g'));
      await s.dispatchAndWait(SetUserAction('admin'));
      await s.dispatchAndWait(SetPasswordAction('pw'));
      await s.dispatchAndWait(LogInAction());
      api
        ..invokes['wy/central/dataflows ▸ node_types'] = [Value.from(catalog)]
        ..invokes['wy/central/dataflows/tank ▸ history'] = [
          Value.from([tank]),
        ]
        ..invokes['wy/central/dataflows ▸ validate'] = [
          Value.from({'ok': true}),
        ]
        ..invokes['wy/central/dataflows ▸ deploy'] = [const VNull()];
      await s.dispatchAndWait(LoadFlowAction('tank'));
    });

    test('a field that gets a wire is pinned, stays pinned after it, and '
        'only then comes off', () {
      expect(rowIds(now(), 'avg'), isNot(contains('p:fn')));
      // The echo of `fn` into the other publish block.
      s.dispatchSync(ConnectPortsAction('avg', 'fn', 'out2', 'in'));
      expect(now().blocks['avg']!.pins['p:fn'], isTrue);
      expect(rowIds(now(), 'avg'), contains('p:fn'));

      s.dispatchSync(SetFieldPinAction('avg', 'p:fn', pinned: false));
      expect(rowIds(now(), 'avg'), contains('p:fn'), reason: 'bound');

      s.dispatchSync(DisconnectEdgeAction('out2', 'in'));
      expect(rowIds(now(), 'avg'), contains('p:fn'), reason: 'as DGLux');

      s.dispatchSync(SetFieldPinAction('avg', 'p:fn', pinned: false));
      expect(rowIds(now(), 'avg'), isNot(contains('p:fn')));
      expect(now().blocks['avg']!.pins, isEmpty);
      expect(s.state.flowEditor.dirty, isTrue);
    });

    test('pins go out with a deploy and survive a reload', () async {
      s
        ..dispatchSync(SetFieldPinAction('avg', 'p:fn', pinned: true))
        ..dispatchSync(SetFieldPinAction('avg', 'p:size_s', pinned: false));
      await s.dispatchAndWait(DeployFlowAction());
      final sent = api.calls.lastWhere((c) => c.action == 'deploy').args!;
      final layout = toDart(sent['def']!['layout'])! as Map<String, Object?>;
      expect(layout['avg~pin~p:fn'], [1, 0]);
      expect(layout['avg~pin~p:size_s'], [0, 0]);

      // The broker hands the definition back as it got it.
      api.invokes['wy/central/dataflows/tank ▸ history'] = [
        Value.from([toDart(sent['def'])]),
      ];
      await s.dispatchAndWait(LoadFlowAction('tank'));
      expect(rowIds(now(), 'avg'), ['in:in', 'p:fn', 'out:out']);
    });

    test('selection: one, many, toggled; the inspector takes one', () {
      s.dispatchSync(SelectBlocksAction(const ['avg', 'text', 'nope']));
      expect(s.state.flowEditor.selection.unlock, {'avg', 'text'});
      expect(s.state.flowEditor.selectedBlock, isNull);
      s.dispatchSync(SelectBlocksAction(const ['text'], toggle: true));
      expect(s.state.flowEditor.selection.unlock, {'avg'});
      expect(s.state.flowEditor.selectedBlock, 'avg');
      s.dispatchSync(SelectBlocksAction(const ['out'], add: true));
      expect(s.state.flowEditor.selection.unlock, {'avg', 'out'});
      s.dispatchSync(SetSelectedBlockAction('level'));
      expect(s.state.flowEditor.selection.unlock, {'level'});
      s.dispatchSync(SetSelectedBlockAction(null));
      expect(s.state.flowEditor.selection, isEmpty);
    });

    test('cut, paste and delete: the clip is kept, pasted blocks are '
        'selected, a foreign text pastes nothing', () {
      final text = clipTextOf(now(), {'avg', 'text'});
      s
        ..dispatchSync(SetClipboardAction(text))
        ..dispatchSync(RemoveBlocksAction(const ['avg', 'text']));
      expect(now().blocks.keys, ['level', 'out', 'out2']);
      expect(now().edges, isEmpty, reason: 'every edge touched them');

      s.dispatchSync(PasteBlocksAction('some text', 100, 100));
      expect(now().blocks.length, 3);

      s.dispatchSync(PasteBlocksAction(s.state.flowEditor.clipboard, 100, 100));
      expect(now().blocks.keys, containsAll(['avg', 'text']));
      expect(now().edges.single.from, 'avg');
      expect(s.state.flowEditor.selection.unlock, {'avg', 'text'});

      s.dispatchSync(PasteBlocksAction(s.state.flowEditor.clipboard, 300, 300));
      expect(s.state.flowEditor.selection.unlock, {'avg1', 'text1'});
      expect(now().edges, hasLength(2));
    });

    test('the clip crosses flows: another flow opened keeps it', () async {
      s.dispatchSync(SetClipboardAction(clipTextOf(now(), {'avg'})));
      api.invokes['wy/central/dataflows/other ▸ history'] = [
        Value.from([
          {'id': 'other', 'version': 1, 'nodes': <String, Object?>{}},
        ]),
      ];
      await s.dispatchAndWait(LoadFlowAction('other'));
      expect(now().blocks, isEmpty);
      s.dispatchSync(PasteBlocksAction(s.state.flowEditor.clipboard, 40, 40));
      expect(now().blocks.keys, ['avg']);
      expect(s.state.flowEditor.undo, hasLength(1));
    });

    test('undo and redo walk every canvas edit', () {
      final start = now();
      s
        ..dispatchSync(AddBlockAction('window', 60, 300))
        ..dispatchSync(
          MoveBlocksAction(const {'avg': (320, 60), 'text': (580, 60)}),
        )
        ..dispatchSync(ConnectPortsAction('level', 'out', 'window1', 'in'))
        ..dispatchSync(SetFieldPinAction('avg', 'p:fn', pinned: true))
        ..dispatchSync(RemoveBlocksAction(const ['out2']));
      final end = now();
      expect(s.state.flowEditor.undo, hasLength(5));

      s.dispatchSync(UndoFlowAction());
      expect(now().blocks.containsKey('out2'), isTrue);
      expect(now().edges, hasLength(5), reason: 'its wire is back too');
      s.dispatchSync(UndoFlowAction());
      expect(now().blocks['avg']!.pins, isEmpty);
      s.dispatchSync(UndoFlowAction());
      expect(now().edges, hasLength(4));
      s.dispatchSync(UndoFlowAction());
      expect(now().blocks['avg']!.x, 300);
      expect(now().blocks['text']!.x, 560, reason: 'one move, one step');
      s.dispatchSync(UndoFlowAction());
      expect(now(), start);
      s.dispatchSync(UndoFlowAction());
      expect(now(), start, reason: 'nothing left');

      for (var i = 0; i < 5; i++) {
        s.dispatchSync(RedoFlowAction());
      }
      expect(now(), end);
      s.dispatchSync(RedoFlowAction());
      expect(now(), end);

      // A new edit after an undo drops what could be redone.
      s
        ..dispatchSync(UndoFlowAction())
        ..dispatchSync(MoveBlocksAction(const {'avg': (0, 0)}));
      expect(s.state.flowEditor.redo, isEmpty);
    });

    test('typing in one field is one step; the history holds 100', () {
      for (final v in [1, 12, 120]) {
        s.dispatchSync(SetBlockParamAction('avg', 'size_s', v));
      }
      expect(s.state.flowEditor.undo, hasLength(1));
      s.dispatchSync(SetBlockParamAction('avg', 'fn', 'max'));
      expect(s.state.flowEditor.undo, hasLength(2));
      s.dispatchSync(UndoFlowAction());
      expect(now().blocks['avg']!.cfg['size_s'], 120);
      s.dispatchSync(UndoFlowAction());
      expect(now().blocks['avg']!.cfg['size_s'], 30);

      // The arrows nudge with one tag: one step.
      for (var i = 1; i <= 3; i++) {
        s.dispatchSync(
          MoveBlocksAction({'avg': (300 + 20.0 * i, 40)}, tag: 'nudge'),
        );
      }
      expect(s.state.flowEditor.undo, hasLength(1));

      for (var i = 0; i < 130; i++) {
        s.dispatchSync(MoveBlocksAction({'avg': (20.0 * i, 400)}));
      }
      expect(s.state.flowEditor.undo, hasLength(undoLimit));
    });

    test('an undo after a deploy keeps the deployed version', () async {
      s.dispatchSync(MoveBlocksAction(const {'avg': (320, 60)}));
      await s.dispatchAndWait(DeployFlowAction());
      expect(now().version, 4);
      s.dispatchSync(UndoFlowAction());
      expect(now().version, 4);
      expect(now().blocks['avg']!.x, 300);
      expect(s.state.flowEditor.dirty, isTrue);
    });

    test('the viewer saves as the inspector types: a parameter into the '
        'config, an operand into `values`', () {
      // What the connector does for both (`_setField`): the field's kind
      // types the text, the inspector's own action writes it.
      void save(String block, String id, String text) {
        final d = now();
        final b = d.blocks[block]!;
        final f = field(d, block, id);
        final edit = fieldEditOf(b, f, d.edges).edit!;
        expect(fieldEditError(text, edit), isNull);
        if (f.operand) {
          s.dispatchSync(
            SetOperandValueAction(block, f.inPort!, typedText(text, edit)),
          );
        } else {
          s.dispatchSync(
            SetBlockParamAction(block, f.spec!.name, typedText(text, edit)),
          );
        }
      }

      save('avg', 'p:size_s', '45');
      expect(now().blocks['avg']!.cfg['size_s'], 45);
      save('avg', 'p:meta', '{"unit": "m", "tags": ["a"]}');
      expect(now().blocks['avg']!.cfg['meta'], {
        'unit': 'm',
        'tags': ['a'],
      });
      save('text', 'in:in.0', 'Level: ');
      expect(operandValueOf(now().blocks['text']!, 'in.0'), 'Level: ');
      save('text', 'p:strict', 'true');
      expect(now().blocks['text']!.cfg['strict'], true);
      save('avg', 'p:fn', 'max');
      expect(now().blocks['avg']!.cfg['fn'], 'max');
      expect(s.state.flowEditor.undo, hasLength(5));
      expect(s.state.flowEditor.dirty, isTrue);
    });
  });
}
