import 'dart:convert';
import 'dart:io';

import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/models/flow_editor_state.dart';
import 'package:business/redux/site/models/site_state.dart';
import 'package:business/wyrm/decode/node_type.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/flow_view/inspector_view.dart';
import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/off.dart';
import 'package:business/wyrm/flow_view/palette_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:business/wyrm/flow_view/summary_view.dart';
import 'package:business/wyrm/flow_view/viewer_view.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/needs_right.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_draft.dart';
import 'package:models/grant.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm, TypeCode, Value;

import 'support/block_types.dart';

/// The flow the agent deployed on the demo's `central` (62 blocks, 74
/// wires), and its catalogue, as the editor reads them.
Object? _json(String name) =>
    jsonDecode(File('test/support/flows/$name').readAsStringSync());

final FlowDraft large = flowDraftOf(
  'dvpsm-bot',
  Value.from(_json('large_flow.json')),
);

final IList<NodeType> types = nodeTypesOf(
  Value.from(_json('large_flow_types.json')),
  where: 'test',
).lock;

const root = 'wy/plant';
const ack = '$root/storage/dvpsm/cmd/ack';

/// The editor of [large] on site `plant`, deployed as version 4 unless
/// [deployed] says otherwise.
AppState stateOf({
  FlowDraft? draft,
  FlowDraft? deployed,
  bool undeployed = false,
  String level = 'config',
}) => AppState.initial().copyWith(
  site: SiteState(
    name: 'plant',
    grants: [Grant(key: '$root/**', level: level)].lock,
  ),
  flowEditor: FlowEditorState(
    flowId: 'dvpsm-bot',
    draft: draft ?? large,
    deployed: undeployed ? null : (deployed ?? large),
    types: types,
    version: undeployed ? 0 : 4,
  ),
);

FlowView viewOf(AppState s) => SelectFlowEditor(s).view('dvpsm-bot');

void main() {
  group('the view of the large flow', () {
    test('every block and every wire, deployed as it is', () {
      final v = viewOf(stateOf());
      expect(v.blocks, hasLength(62));
      expect(v.wires, hasLength(74));
      expect(v.status, EditorStatus.deployed);
      expect(v.version, 4);
      expect(v.dot, isFalse);
      expect(v.deployOff, const OffFor(DeployOffReason.nothing));
      expect(v.flowName, 'dvpsm-bot');
      expect(v.isNew, isFalse);
      expect(v.inspector, isNull);
      expect(v.summary, isNotNull);
      final c = v.blocks.firstWhere((b) => b.id == 'c_ack');
      expect(c.role, BlockRole.node);
      expect(c.caption, ['storage/dvpsm/cmd']);
      expect(c.width, blockWidthOf(BlockRole.node));
      expect(c.boundary, isNull);
      final inv = v.blocks.firstWhere((b) => b.id == 's_ack_0');
      expect(inv.role, BlockRole.action);
      expect(inv.caption, ['dvpsm', 'send']);
    });

    test('a draft that differs, and what Deploy lacks', () {
      final moved = large.copyWith(
        blocks: large.blocks.update(
          'c_ack',
          (b) => b.copyWith(cfg: b.cfg.add('key', 'storage/x')),
        ),
      );
      final v = viewOf(stateOf(draft: moved, level: 'write'));
      expect(v.status, EditorStatus.draft);
      expect(v.dot, isTrue);
      expect(
        v.deployOff,
        const OffNeeds<DeployOffReason>(
          NeedsRight(Perm.config, 'dataflows'),
        ),
      );
      expect(viewOf(stateOf(draft: moved)).deployOff, isNull);
      final loading = AppState.initial();
      expect(
        SelectFlowEditor(loading).view('x').status,
        EditorStatus.loading,
      );
    });

    test('a key nothing reads leaves the view as it was; a key a block '
        'reads changes it', () {
      final s = stateOf();
      final v = viewOf(s);
      final other = s.copyWith.live(
        values: {
          '$root/downstream/elsewhere/x': LiveValue(
            time: DateTime.utc(2026),
            value: 1,
          ),
        }.lock,
      );
      expect(identical(viewOf(other), v), isTrue);
      final read = other.copyWith.live(
        values: other.live.values.add(
          ack,
          LiveValue(time: DateTime.utc(2026), value: 49),
        ),
      );
      final w = viewOf(read);
      expect(identical(w, v), isFalse);
      final row = w.blocks
          .firstWhere((b) => b.id == 'c_ack')
          .rows
          .firstWhere((r) => r.outPort == 'out');
      expect(row.value, '49');
      // The same state twice: the same view.
      expect(identical(viewOf(read), w), isTrue);
    });

    test('what the editor follows', () {
      final f = viewOf(stateOf()).follow;
      expect(f.watch, contains(ack));
      expect(f.watch, contains('$root/dataflows/dvpsm-bot'));
      expect(f.details, contains('$root/downstream/telegram-process/dvpsm'));
      expect(f.run, isNotNull);
    });

    test('wires into an action block write', () {
      final v = viewOf(stateOf());
      final w = v.wires.firstWhere((w) => w.to == 's_status_0');
      expect(w.writes, isTrue);
      expect(v.wires.firstWhere((w) => w.to == 'e_status').writes, isFalse);
    });
  });

  group('the inspector', () {
    test('a point', () {
      final s = stateOf().copyWith.flowEditor(selectedBlock: 'c_ack');
      final v = viewOf(s);
      expect(v.selected, 'c_ack');
      expect(v.removable, isTrue);
      final i = v.inspector!;
      expect(i.kind, InspectorKind.node);
      expect(i.note, InspectorNote.treeNode);
      expect(v.summary, isNull);
      final key = i.rows.whereType<ParamRowView>().firstWhere(
        (r) => r.id == const FieldId.param('key'),
      );
      expect(key.value, 'storage/dvpsm/cmd/ack');
      expect(key.editor, ParamRowEditor.text);
    });

    test('an action block: its trigger runs only on the deployed flow', () {
      // Its trigger unbound: a Run button.
      final free = large.copyWith(
        edges: large.edges.removeWhere(
          (e) => e.to == 's_ack_0' && e.toPort == 'trigger',
        ),
      );
      final s = stateOf(
        draft: free,
        deployed: free,
      ).copyWith.flowEditor(selectedBlock: 's_ack_0');
      final i = viewOf(s).inspector!;
      expect(i.kind, InspectorKind.action);
      expect(i.note, InspectorNote.actionBlock);
      final run = i.rows.whereType<RunRowView>().single;
      expect(run.off, isNull);
      final undeployed = stateOf(
        draft: free,
        undeployed: true,
      ).copyWith.flowEditor(selectedBlock: 's_ack_0');
      expect(
        viewOf(undeployed).inspector!.rows.whereType<RunRowView>().single.off,
        const OffFor(RunOffReason.notDeployed),
      );
      final args = i.rows.whereType<ArgRowView>().toList();
      expect([for (final a in args) a.name], containsAll(['text', 'to']));
      expect(args.first.group, FieldGroup.arguments);
      // Bound, the trigger shows what comes in.
      final bound = viewOf(
        stateOf().copyWith.flowEditor(selectedBlock: 's_ack_0'),
      );
      expect(
        bound.inspector!.rows.whereType<BoundRowView>().map((r) => r.id),
        contains(const FieldId.input('trigger')),
      );
    });

    test('run off: a right the user lacks', () {
      expect(
        runOffOf(
          large.blocks['s_ack_0']!,
          caps: const FlowCaps(trigger: true),
          isNew: false,
          deployed: true,
          differs: false,
          engineId: 's_ack_0',
          write: const NeedsRight(Perm.write, 'dataflows/dvpsm-bot'),
        ),
        const OffNeeds<RunOffReason>(
          NeedsRight(Perm.write, 'dataflows/dvpsm-bot'),
        ),
      );
      expect(
        runOffOf(
          large.blocks['s_ack_0']!,
          caps: const FlowCaps(),
          isNew: false,
          deployed: true,
          differs: false,
          engineId: 's_ack_0',
          write: null,
        ),
        const OffFor(RunOffReason.noBroker),
      );
    });
  });

  test('the summary of the flow', () {
    final v = viewOf(stateOf());
    final sum = v.summary!;
    expect(sum.name, 'dvpsm-bot');
    expect(sum.version, 4);
    expect(sum.mayWrite, Perm.write);
    expect(sum.values, ValuesFrom.deployed);
    expect(sum.reads, isNotEmpty);
    expect(sum.writes, isNotEmpty);
    expect(sum.problems, isEmpty);
    final undeployed = viewOf(stateOf(undeployed: true)).summary!;
    expect(undeployed.version, 0);
    expect(undeployed.values, isNull);
  });

  test('the context menu', () {
    final s = stateOf();
    final ed = SelectFlowEditor(s);
    final canvas = ed.menu('dvpsm-bot', const MenuAsk(ISetConst({})));
    expect(canvas.block, isNull);
    expect(canvas.flow, 'dvpsm-bot');
    expect(canvas.blocksInFlow, 62);
    expect(
      canvas.items.firstWhere((i) => i.command == MenuCommand.undo).off,
      MenuOffReason.nothingToUndo,
    );
    expect(
      canvas.items.firstWhere((i) => i.command == MenuCommand.cut).off,
      MenuOffReason.nothingSelected,
    );
    final one = ed.menu(
      'dvpsm-bot',
      const MenuAsk(
        ISetConst({'c_ack'}),
        block: 'c_ack',
        row: FieldId.output('out'),
      ),
    );
    expect(one.block, 'c_ack');
    expect(one.blockType, 'subscribe');
    expect(one.fields, isNotEmpty);
    expect(one.unpin?.id, const FieldId.output('out'));
    expect(
      one.items.firstWhere((i) => i.command == MenuCommand.editCustomBlock).off,
      isNotNull,
    );
  });

  test('the palette: the catalogue and its sides', () {
    final v = viewOf(stateOf());
    expect(v.catalog, hasLength(types.length));
    final sub = v.catalog.firstWhere((c) => c.type.wire == 'subscribe');
    expect(sub.side, PaletteSide.input);
    expect(
      v.catalog.firstWhere((c) => c.type.wire == 'set').side,
      PaletteSide.output,
    );
    expect(v.tree, isNull);
    expect(v.myBlocks, isEmpty);
    expect(v.myBlocksOff, !flowCapsOf(types).blocks);
  });

  test('the Tree tab: sections, an open node, a value and an action', () {
    const plc = '$root/downstream/plc';
    final s = stateOf().copyWith
        .flowEditor(palette: PaletteTab.tree)
        .copyWith
        .nodes(
          table: {
            plc: const NodeInfo(key: plc, name: 'plc', hasChildren: true),
            '$plc/level': const NodeInfo(
              key: '$plc/level',
              name: 'level',
              type: TypeCode.number,
              unit: 'm',
              writable: Perm.write,
            ),
          }.lock,
          view: ['$root/downstream', plc, '$plc/level'].lock,
          expanded: {'$root/downstream', plc}.lock,
        )
        .copyWith
        .live(
          values: {
            '$plc/level': LiveValue(time: DateTime.utc(2026), value: 2.5),
          }.lock,
        );
    final tree = viewOf(s).tree!;
    expect(
      [for (final e in tree) e.key],
      [
        '$root/downstream',
        plc,
        '$plc/level',
        '$root/dataflows',
        '$root/storage',
      ],
    );
    final leaf = tree.whereType<TreeNodeEntry>().firstWhere(
      (e) => e.key == '$plc/level',
    );
    expect(leaf.value, '2.5 m');
    expect(leaf.writable, isTrue);
    expect(leaf.entry, const PointPick('$plc/level'));
    expect(viewOf(s).follow.watch, contains('$plc/*'));
    // A filter keeps what holds it and the nodes above.
    final q = viewOf(s.copyWith.flowEditor(treeQuery: 'lev')).tree!;
    expect([for (final e in q) e.key], ['$root/downstream', plc, '$plc/level']);
  });

  test('the scope prompt of a key that got a wire', () {
    final s = stateOf().copyWith.flowEditor(scopePrompt: 'c_ack');
    final p = viewOf(s).prompt!;
    expect(p.block, 'c_ack');
    expect(p.row, const FieldId.param('key'));
    expect(p.value, 'storage/dvpsm/cmd/**');
    expect(p.suggestions, contains('downstream/**'));
    expect(SelectFlowEditor(s).scopeProblem(''), ScopeProblem.empty);
  });

  test('the custom block dialog and the checks of names', () {
    final s = stateOf().copyWith.flowEditor(
      selection: {'c_status', 'e_status'}.lock,
    );
    final ed = SelectFlowEditor(s);
    final c = ed.customBlock('dvpsm-bot')!;
    expect(
      customBlockOf(large, {'c_status'}.lock, customBlocks: false),
      isNull,
    );
    expect(c.name, 'block1');
    expect(c.blocks, 2);
    expect(c.outputs, isNotEmpty);
    expect(c.outputs.first.outside, isNotEmpty);
    expect(ed.blockNameProblem('dvpsm-bot', 'a b'), BlockNameProblem.name);
    expect(ed.blockNameProblem('dvpsm-bot', 'free'), isNull);
    expect(
      customBlockSpecOf(
        name: 'b',
        description: '',
        inputs: ['x'],
        outputs: [],
        defaults: {'x': '2'},
      ).defaults,
      {'x': 2},
    );
  });

  test('a wire refused: into its own block', () {
    final ed = SelectFlowEditor(stateOf());
    final r = ed.refusal(
      'dvpsm-bot',
      const WireAsk(
        PortEnd('c_ack', 'out'),
        'c_ack',
        FieldId.param('key'),
      ),
    )!;
    expect(r.refused.reason, BindRefusal.self);
    expect(r.label, isNotEmpty);
  });

  test('the viewer of a field and what its text must be', () {
    final s = stateOf().copyWith.flowEditor(
      viewedField: const FieldAt('s_ack_0', FieldId.param('interval_ms')),
    );
    final v = viewOf(s).viewer! as FieldViewerView;
    expect(v.block, 's_ack_0');
    expect(v.field, 'interval_ms');
    expect(v.edit?.mode, ViewerEditMode.number);
    expect(v.locked, isNull);
    final ed = SelectFlowEditor(s);
    expect(ed.viewerTextError('dvpsm-bot', 'x'), FieldEditError.number);
    expect(ed.viewerTextError('dvpsm-bot', '5'), isNull);
    final out = stateOf().copyWith.flowEditor(
      viewedField: const FieldAt('c_ack', FieldId.output('out')),
    );
    expect((viewOf(out).viewer! as FieldViewerView).locked, FieldLocked.output);
  });
}
