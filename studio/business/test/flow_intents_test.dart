// One action per intent of the flow editor (studio-rules §9): what the
// page asks for is one dispatch, and the action carries out its steps.

import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/bind_field_action.dart';
import 'package:business/redux/flow_editor/actions/cancel_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/close_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/drop_point_on_input_action.dart';
import 'package:business/redux/flow_editor/actions/edit_scope_action.dart';
import 'package:business/redux/flow_editor/actions/flow_edit_action.dart';
import 'package:business/redux/flow_editor/actions/follow_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/open_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/paste_blocks_at_action.dart';
import 'package:business/redux/flow_editor/actions/pick_palette_entry_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_field_action.dart';
import 'package:business/redux/flow_editor/actions/resize_block_action.dart';
import 'package:business/redux/flow_editor/actions/save_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/select_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/set_flow_ports_action.dart';
import 'package:business/redux/flow_editor/actions/set_viewed_field_action.dart';
import 'package:business/redux/flow_editor/actions/show_palette_tab_action.dart';
import 'package:business/redux/flow_editor/actions/type_field_action.dart';
import 'package:business/redux/flow_editor/actions/unbind_field_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/mappers/block_cfg.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edit.dart';
import 'package:models/live_value.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/port_end.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/catalog_0229.dart';
import 'support/fake_wyrm.dart';

const _root = 'wy/central';

/// `level → count`: a point read, and a counter whose `step` has a port.
final Map<String, Object> _tank = {
  'id': 'tank',
  'version': 3,
  'nodes': {
    'level': {'type': 'subscribe', 'key': 'downstream/plc/level'},
    'count': {'type': 'counter'},
  },
  'edges': [
    ['level.out', 'count.in'],
  ],
};

void main() {
  late FakeWyrmApi api;
  late FakeClipboard clipboard;
  late Store<AppState> s;

  FlowDraft now() => s.state.flowEditor.draft!;

  /// The id of the field of [block] its input [port] feeds.
  RowId rowOf(String block, String port) =>
      SelectFlowEditor(s.state).base.fields[block]!
          .firstWhere((f) => f.inPort == port)
          .id;

  setUp(() async {
    final login = FakeLogin();
    api = login.session.api;
    clipboard = FakeClipboard();
    s = fakeStore(login: login, clipboard: clipboard);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    api
      ..invokes['$_root/dataflows ▸ node_types'] = [Value.from(catalog0229())]
      ..invokes['$_root/dataflows/tank ▸ history'] = [
        Value.from([_tank]),
      ]
      ..invokes['$_root/dataflows ▸ validate'] = [
        Value.from({'ok': true}),
      ]
      ..invokes['$_root/dataflows ▸ list_blocks'] = [
        Value.from(<Object?>[]),
      ];
    await s.dispatchAndWait(OpenFlowEditorAction('tank'));
  });

  group('open, follow and close', () {
    test('open reads the flow, follows its keys and validates', () {
      final ed = s.state.flowEditor;
      expect(ed.route, 'tank');
      expect(ed.flowId, 'tank');
      expect(now().blocks.keys, containsAll(['level', 'count']));
      // What the first view shows (the flow's own `~val`); what the read
      // brought follows when the page reconciles its view.
      expect(s.state.live.watched['$_root/dataflows/tank'], 1);
      expect(api.calls.where((c) => c.action == 'validate'), isNotEmpty);
    });

    test('close lets go of what open and follow watched', () {
      final view = SelectFlowEditor(s.state).view('tank').follow;
      s.dispatchSync(
        FollowFlowEditorAction(
          FlowFollow(
            watch: {'$_root/dataflows/tank'}.lock,
            details: const ISetConst({}),
            run: view.run,
          ),
          view,
        ),
      );
      expect(s.state.live.watched['$_root/downstream/plc/level'], 1);
      s.dispatchSync(CloseFlowEditorAction('tank'));
      final watched = s.state.live.watched;
      expect(watched.containsKey('$_root/dataflows/tank'), isFalse);
      expect(watched.containsKey('$_root/downstream/plc/level'), isFalse);
    });

    test('follow watches what came and lets go of what went', () {
      const a = FlowFollow(
        watch: ISetConst({'$_root/storage/a'}),
        details: ISetConst({}),
        run: null,
      );
      const b = FlowFollow(
        watch: ISetConst({'$_root/storage/b'}),
        details: ISetConst({}),
        run: null,
      );
      s
        ..dispatchSync(FollowFlowEditorAction(FlowFollow.none, a))
        ..dispatchSync(FollowFlowEditorAction(a, b));
      expect(s.state.live.watched.containsKey('$_root/storage/a'), isFalse);
      expect(s.state.live.watched['$_root/storage/b'], 1);
    });
  });

  group('the palette', () {
    test('a tapped engine type goes a step below; a point is read or '
        'written', () {
      final n = now().blocks.length;
      s.dispatchSync(PickPaletteEntryAction(EnginePick(bt('counter'))));
      final added = now().blocks.values.last;
      expect(added.type, bt('counter'));
      expect((added.x, added.y), (60 + 30.0 * n, 60 + 30.0 * n));

      s.dispatchSync(
        PickPaletteEntryAction(
          const PointPick('$_root/downstream/plc/valve'),
          x: 400,
          y: 200,
          write: true,
        ),
      );
      final set = now().blocks.values.last;
      expect(set.type.known, KnownBlock.set);
      expect(set.cfg['path'], 'downstream/plc/valve');
      expect((set.x, set.y), (400.0, 200.0));

      s.dispatchSync(
        PickPaletteEntryAction(const PointPick('$_root/storage/sp')),
      );
      expect(now().blocks.values.last.cfg['key'], 'storage/sp');
    });

    test('My blocks is off without custom blocks; the tree is a tab', () {
      s.dispatchSync(ShowPaletteTabAction(PaletteTab.tree));
      expect(s.state.flowEditor.palette, PaletteTab.tree);
      if (!SelectFlowEditor(s.state).caps.blocks) {
        s.dispatchSync(ShowPaletteTabAction(PaletteTab.my));
        expect(s.state.flowEditor.palette, PaletteTab.tree);
      }
    });

    test('a point dropped on an input reads it into that input', () {
      s.dispatchSync(
        DropPointOnInputAction(
          '$_root/storage/step',
          PortEnd('count', 'in.step'),
        ),
      );
      final sub = now().blocks.values.last;
      expect(sub.type.known, KnownBlock.subscribe);
      expect(sub.cfg['key'], 'storage/step');
      expect(
        now().edges.where((e) => e.to == 'count' && e.toPort == 'in.step'),
        hasLength(1),
      );
    });
  });

  group('fields', () {
    test('a typed number goes into the parameter', () {
      s.dispatchSync(TypeFieldAction('count', rowOf('count', 'in.step'), '5'));
      expect(now().blocks['count']!.cfg['step'], 5);
    });

    test('bind, then unbind keeps the last value shown; rebind moves the '
        'wire', () {
      final step = rowOf('count', 'in.step');
      s.dispatchSync(
        BindFieldAction('count', step, PortEnd('level', 'out')),
      );
      expect(
        now().edges.where((e) => e.to == 'count' && e.toPort == 'in.step'),
        hasLength(1),
      );
      s
        ..dispatchSync(
          SetFlowPortsAction(
            {
              portKey(PortSide.input, 'count', 'in.step'): LiveValue(
                time: DateTime.utc(2026),
                value: 7,
              ),
            },
          ),
        )
        ..dispatchSync(UnbindFieldAction('count', step));
      expect(
        now().edges.where((e) => e.toPort == 'in.step'),
        isEmpty,
      );
      expect(now().blocks['count']!.cfg['step'], 7);

      s
        ..dispatchSync(ConnectPortsAction('level', 'out', 'count', 'in.step'))
        ..dispatchSync(
          RebindFieldAction(
            PortEnd('count', 'in.step'),
            PortEnd('count', 'in.initial'),
          ),
        );
      expect(
        now().edges.where((e) => e.to == 'count').map((e) => e.toPort),
        containsAll(['in', 'in.initial']),
      );
      expect(now().edges.where((e) => e.toPort == 'in.step'), isEmpty);
    });

    test('the scope prompt: cancel drops the wire into the key, save '
        'writes the scope', () {
      s
        ..dispatchSync(
          PickPaletteEntryAction(EnginePick(bt('subscribe')), x: 0, y: 0),
        )
        ..dispatchSync(
          ConnectPortsAction('count', 'out', 'subscribe1', 'in.key'),
        );
      expect(s.state.flowEditor.scopePrompt, 'subscribe1');
      s.dispatchSync(CancelScopePromptAction());
      expect(s.state.flowEditor.scopePrompt, isNull);
      expect(now().edges.where((e) => e.to == 'subscribe1'), isEmpty);

      s.dispatchSync(
        EditScopeAction('subscribe1', const FieldId.param('key_scope')),
      );
      expect(s.state.flowEditor.scopePrompt, 'subscribe1');
      s.dispatchSync(SaveScopePromptAction('downstream/**'));
      expect(s.state.flowEditor.scopePrompt, isNull);
      expect(now().blocks['subscribe1']!.textOf('key_scope'), 'downstream/**');
    });
  });

  group('the canvas', () {
    test('copy writes both clipboards; a text that is not blocks pastes '
        'nothing; without a system clipboard the own one pastes', () async {
      s
        ..dispatchSync(SelectBlocksAction(const ['count']))
        ..dispatchSync(FlowEditAction(FlowEdit.copy));
      await pumpEventQueue();
      final own = s.state.flowEditor.clipboard;
      expect(own, contains('"count"'));
      expect(clipboard.text, own);

      clipboard.text = 'hello';
      final before = now().blocks.length;
      await s.dispatchAndWait(PasteBlocksAtAction(x: 10, y: 10));
      expect(now().blocks.length, before);

      clipboard.text = null;
      await s.dispatchAndWait(PasteBlocksAtAction(x: 10, y: 10));
      expect(now().blocks.length, before + 1);
    });

    test('cut removes what it copied', () {
      s
        ..dispatchSync(SelectBlocksAction(const ['count']))
        ..dispatchSync(FlowEditAction(FlowEdit.cut));
      expect(now().blocks.containsKey('count'), isFalse);
      expect(s.state.flowEditor.clipboard, contains('"count"'));
    });

    test('Esc closes the viewer first, then the selection', () {
      s
        ..dispatchSync(SelectBlocksAction(const ['count']))
        ..dispatchSync(
          SetViewedFieldAction(
            FieldAt('count', rowOf('count', 'in.step')),
          ),
        )
        ..dispatchSync(FlowEditAction(FlowEdit.escape));
      expect(s.state.flowEditor.viewedField, isNull);
      expect(s.state.flowEditor.selection, isNotEmpty);
      s.dispatchSync(FlowEditAction(FlowEdit.escape));
      expect(s.state.flowEditor.selection, isEmpty);
    });

    test('+ and − of a variadic block', () {
      s.dispatchSync(
        PickPaletteEntryAction(EnginePick(bt('make_array')), x: 0, y: 0),
      );
      final id = now().blocks.values.last.id;
      List<Object?> inputs() =>
          (now().blocks[id]!.cfg['inputs'] as List<Object?>?) ??
          const ['0', '1'];
      final n = inputs().length;
      s.dispatchSync(ResizeBlockAction(id, add: true));
      expect(inputs().length, n + 1);
    });
  });
}

BlockType bt(String wire) => BlockType.fromWire(wire);
