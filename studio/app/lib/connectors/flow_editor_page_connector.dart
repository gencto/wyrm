import 'dart:async';
import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/add_block_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/move_block_action.dart';
import 'package:business/redux/flow_editor/actions/new_flow_action.dart';
import 'package:business/redux/flow_editor/actions/remove_block_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_palette_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/flow_editor/actions/watch_flow_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/pages/flow_editor_page.dart';

import '../navigation/app_router.dart';
import '../navigation/go_action.dart';
import 'flows_page_connector.dart';

/// Block types that read from the tree (IN, teal) and that write to it
/// (OUT, ember) in the palette; everything between is logic (FX).
const _sources = {
  'subscribe',
  'liveliness',
  'timer',
  'history',
  'dql',
  'const',
};
const _sinks = {'set', 'invoke', 'publish'};

@RoutePage()
class FlowEditorPageConnector extends StatelessWidget {
  const FlowEditorPageConnector({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) {
      store.dispatchSync(WatchKeysAction(_watch(store.state, id)));
      unawaited(_open(store));
    },
    onWillChange: (context, store, before, now) {
      // Points of the Tree tab and of the blocks, and the flow's own value.
      if (!listEquals(before.watch, now.watch)) {
        store
          ..dispatchSync(WatchKeysAction(now.watch))
          ..dispatchSync(UnwatchKeysAction(before.watch));
      }
    },
    onDispose: (store) => store
      ..dispatchSync(UnwatchKeysAction(_watch(store.state, id)))
      ..dispatchSync(WatchFlowAction(null)),
    builder: (context, vm) => FlowEditorPage(
      flowsLabel: S.current.wsFlows,
      flowLabel: vm.flowLabel,
      blockLabel: vm.blockLabel,
      state: vm.state,
      stateDot: vm.stateDot,
      validateLabel: S.current.validate,
      deployLabel: S.current.deploy,
      deployReason: vm.deployReason,
      onDeploy: vm.onDeploy,
      onValidate: vm.onValidate,
      onClose: vm.onClose,
      onFlows: vm.onClose,
      paletteTabs: [
        TabItemVm(id: 'blocks', label: S.current.paletteBlocks),
        TabItemVm(
          id: 'my',
          label: S.current.paletteMyBlocks,
          disabledReason: S.current.myBlocksReason,
        ),
        TabItemVm(id: 'tree', label: S.current.paletteTree),
      ],
      paletteTab: vm.paletteTab,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.palette,
      searchHint: vm.paletteTab == 'tree'
          ? S.current.findInTree
          : S.current.findBlock,
      paletteNotes: vm.paletteTab == 'tree'
          ? [
              PaletteNoteVm(S.current.treePoint, S.current.treePointNote),
              PaletteNoteVm(
                S.current.treeAction,
                S.current.treeActionNote,
                ember: true,
              ),
            ]
          : const [],
      onPick: vm.onPick,
      blocks: vm.blocks,
      wires: vm.wires,
      blockActions: FlowBlockActions(
        onSelect: vm.onSelect,
        onMove: (_, _) {},
        onMoveEnd: (_) {},
        onBind: vm.onBind,
        onUnbind: vm.onUnbind,
        onDropEntry: vm.onDropEntry,
        onResize: vm.onResize,
      ),
      onClear: vm.onClear,
      onMove: vm.onMove,
      onDrop: vm.onDrop,
      legend: FlowLegendVm(
        reads: S.current.legendReads,
        writes: S.current.legendWrites,
        free: S.current.legendFree,
        readOnly: S.current.legendReadOnly,
      ),
      nameField: vm.nameField,
      inspectorKind: vm.inspectorKind,
      inspectorTitle: vm.inspectorTitle,
      inspectorNote: vm.inspectorNote,
      inspectorRows: vm.inspectorRows,
      summary: vm.summary,
      inspectorFooter: [
        S.current.flowPropertiesNote,
        S.current.flowPropertiesNote2,
      ],
      onFieldChanged: vm.onFieldChanged,
      onFieldUnbind: vm.onFieldUnbind,
      onFieldBind: vm.onFieldBind,
      onProblem: vm.onProblem,
      removeLabel: S.current.removeBlock,
      onRemove: vm.onRemove,
      onLogo: vm.onLogo,
    ),
  );

  Future<void> _open(Store<AppState> store) async {
    final isNew = id == newFlowId;
    await store.dispatchAndWait(LoadFlowAction(isNew ? '' : id, isNew: isNew));
    // Live values exist for the deployed version only (ADR 0038 §3, §5).
    store.dispatchSync(WatchFlowAction(isNew ? null : id));
    await store.dispatchAndWait(ValidateFlowAction());
  }

  /// What the editor subscribes to: the parents of the Tree tab's points
  /// while it is shown, the points the blocks read and write, and the
  /// flow's own `~val` (version, deployed by).
  static List<String> _watch(AppState s, String id) {
    final root = SelectSite(s).root;
    if (root == null) {
      return const [];
    }
    final nodes = SelectNodes(s);
    final ed = SelectFlowEditor(s);
    return {
      if (ed.palette == 'tree')
        for (final k in nodes.view)
          if (nodes.table[k]?.type != null)
            '${k.substring(0, k.lastIndexOf('/'))}/*',
      for (final b in ed.draft?.blocks.values ?? const <FlowBlock>[])
        if (b.type != 'invoke')
          if (pointOf(b) case final k?) _full(root, k),
      if (id != newFlowId) '$root/dataflows/$id',
    }.toList();
  }
}

/// A point key of a definition (relative to the site, or full) as a full key.
String _full(String root, String key) =>
    key.startsWith('wy/') ? key : '$root/$key';

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, FlowEditorPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final root = site.root ?? '';
    final ed = flowEditor;
    final d = ed.draft;
    final types = {for (final t in ed.types) t.type: t};
    final isNew = connector.id == newFlowId;
    final id = d?.id ?? '';
    final sel = ed.selectedBlock;
    final b = sel == null ? null : d?.blocks[sel];
    final deployed = ed.deployed;
    final differs =
        d != null && (deployed == null || defOf(d, 0) != defOf(deployed, 0));
    final problems = ed.problems;
    final busy = state.wait.isWaitingForType<DeployFlowAction>();
    final edges = d?.edges ?? const IListConst<FlowEdge>([]);
    final blocks = d?.blocks ?? const IMapConst<String, FlowBlock>({});
    final fields = {
      for (final x in blocks.values) x.id: fieldsOf(types[x.type], x),
    };
    // Rows a block draws: its own, and any field a wire touches.
    final rows = {
      for (final x in blocks.values)
        x.id: [
          for (final f in fields[x.id]!)
            if (f.onBlock ||
                edges.any(
                  (e) =>
                      (e.to == x.id && e.toPort == f.inPort) ||
                      (e.from == x.id && e.fromPort == f.outPort),
                ))
              f,
        ],
    };
    String labelOf(String block, String port) =>
        fields[block]?.where((f) => f.outPort == port).firstOrNull?.label ??
        port;

    return _Vm(
      watch: FlowEditorPageConnector._watch(state, connector.id),
      flowLabel: id.isNotEmpty ? id : S.current.newDataflow,
      blockLabel: sel,
      state: switch (ed) {
        _ when d == null => S.current.loading,
        _ when busy => S.current.deploying,
        _ when differs || isNew => S.current.draftSaved,
        _ => S.current.versionDeployed(ed.version),
      },
      stateDot: d != null && !busy && (differs || isNew),
      deployReason: d == null
          ? S.current.loading
          : (!differs && !isNew
                ? S.current.nothingToDeploy
                : (problems.isNotEmpty
                      ? S.current.fixFirst
                      : site.needs('config', '$root/dataflows'))),
      paletteTab: ed.palette,
      palette: ed.palette == 'tree' ? _tree(root, blocks) : _catalog(ed.types),
      blocks: [
        for (final x in blocks.values)
          _block(x, types[x.type], rows[x.id]!, d!, root, x.id == sel),
      ],
      wires: [
        for (final e in edges)
          () {
            final writes = writingTypes.contains(blocks[e.to]?.type);
            // A parameter's echo sends at start: into a device it writes at
            // every deploy (ADR 0038 §6).
            final fromParam =
                fields[e.from]
                    ?.where((f) => f.outPort == e.fromPort)
                    .firstOrNull
                    ?.kind ==
                FieldKind.param;
            return FlowWireVm(
              e.from,
              e.fromPort,
              e.to,
              e.toPort,
              writes: writes,
              warning: writes && fromParam ? S.current.firesAtDeploy : null,
              warningNote: S.current.firesAtDeployNote,
            );
          }(),
      ],
      nameField: isNew
          ? ParamFieldVm(
              id: 'flow-id',
              label: S.current.flowName,
              kind: ParamKind.text,
              value: id,
              required: true,
              hint: 'tank_level',
              onChanged: (v) =>
                  dispatchSync(NewFlowAction('${v ?? ''}'.trim())),
            )
          : null,
      inspectorKind: b == null ? '' : _kindLabel(roleOf(b.type)),
      inspectorTitle: b?.id ?? '',
      inspectorNote: switch (b) {
        null => '',
        _ when roleOf(b.type) == BlockRole.node => S.current.noteTreeNode,
        _ when roleOf(b.type) == BlockRole.action => S.current.noteAction,
        _ => types[b.type]?.description ?? '',
      },
      inspectorRows: b == null
          ? const []
          : [
              for (final f in fields[b.id]!)
                _inspectorRow(b, f, d!, root, labelOf),
            ],
      summary: b == null ? _summary(root, id, d, problems) : null,
      onDeploy: () => unawaited(dispatchAndWait(DeployFlowAction())),
      onValidate: () => unawaited(dispatchAndWait(ValidateFlowAction())),
      onClose: () => dispatch(GoAction.pop()),
      onPaletteTab: (t) {
        if (t != 'my') {
          dispatchSync(SetPaletteAction(t));
        }
      },
      onPick: (entry) => _add(
        entry,
        60 + 30.0 * (blocks.length % 8),
        60 + 30.0 * (blocks.length % 8),
      ),
      onDrop: _add,
      onClear: () => dispatchSync(SetSelectedBlockAction(null)),
      onMove: (x, px, py) => dispatchSync(MoveBlockAction(x, px, py)),
      onSelect: (x) => dispatchSync(SetSelectedBlockAction(x)),
      onBind: (from, to, port) =>
          dispatchSync(ConnectPortsAction(from.block, from.port, to, port)),
      onUnbind: _unbind,
      onDropEntry: (entry, block, port) {
        final target = blocks[block];
        if (target == null || !entry.startsWith('key:')) {
          return;
        }
        dispatchSync(
          AddBlockAction(
            'subscribe',
            (target.x - 260).clamp(0, double.infinity).toDouble(),
            target.y,
            cfg: {'key': _rel(entry.substring(4))},
            into: (block, port),
          ),
        );
      },
      onResize: (block, {required add}) =>
          dispatchSync(ResizeInputsAction(block, add: add)),
      onFieldChanged: (row, text) {
        if (b == null) {
          return;
        }
        final f = fields[b.id]!.where((x) => x.id == row).firstOrNull;
        if (f == null) {
          return;
        }
        if (f.kind == FieldKind.arg) {
          final args = Map<String, Object?>.of(
            (b.cfg['args'] as Map?)?.cast<String, Object?>() ?? const {},
          );
          args[f.label] = _typed(text, 'dynamic');
          dispatchSync(SetBlockParamAction(b.id, 'args', args));
        } else if (f.spec case final p?) {
          dispatchSync(
            SetBlockParamAction(
              b.id,
              p.name,
              p.choices.isNotEmpty ? text : _typed(text, p.type),
            ),
          );
        }
      },
      onFieldUnbind: (row) {
        if (b != null) {
          _unbind(b.id, row);
        }
      },
      onFieldBind: (row, from) {
        final port = b == null
            ? null
            : fields[b.id]!.where((x) => x.id == row).firstOrNull?.inPort;
        if (b != null && port != null && from.block != b.id) {
          dispatchSync(ConnectPortsAction(from.block, from.port, b.id, port));
        }
      },
      onProblem: (x) => dispatchSync(SetSelectedBlockAction(x)),
      onRemove: sel == null ? null : () => dispatchSync(RemoveBlockAction(sel)),
      onLogo: () => dispatch(GoAction.navigate(const ExplorerRoute())),
    );
  }

  /// Unbinds the field [row] of [block]; a typed parameter keeps the last
  /// value it had.
  void _unbind(String block, String row) {
    final d = flowEditor.draft;
    final b = d?.blocks[block];
    if (b == null) {
      return;
    }
    final t = flowEditor.types.where((t) => t.type == b.type).firstOrNull;
    final f = fieldsOf(t, b).where((x) => x.id == row).firstOrNull;
    final port = f?.inPort;
    if (f == null || port == null) {
      return;
    }
    final last = flowEditor.ports[portKey('in', block, port)]?.value;
    dispatchSync(
      DisconnectEdgeAction(
        block,
        port,
        param: f.spec?.name,
        keep: f.typed ? last : null,
      ),
    );
  }

  void _add(String entry, double x, double y) {
    if (entry.startsWith('type:')) {
      dispatchSync(AddBlockAction(entry.substring(5), x, y));
    } else if (entry.startsWith('key:')) {
      dispatchSync(
        AddBlockAction(
          'subscribe',
          x,
          y,
          cfg: {'key': _rel(entry.substring(4))},
        ),
      );
    } else if (entry.startsWith('act:')) {
      final full = entry.substring(4);
      final i = full.lastIndexOf('/');
      final node = full.substring(0, i);
      final name = full.substring(i + 1);
      final action = nodes.detail[node]?.actions
          .where((a) => a.name == name)
          .firstOrNull;
      dispatchSync(
        AddBlockAction(
          'invoke',
          x,
          y,
          cfg: {
            'path': _rel(node),
            'action': name,
            'on': 'rising',
            // Only arguments with a default: an empty one would be sent.
            if (action != null &&
                action.params.any((p) => p.defaultValue != null))
              'args': {
                for (final p in action.params)
                  p.name: ?p.defaultValue,
              },
          },
        ),
      );
    }
  }

  /// A full key as the definition writes it, relative to the site.
  static String _rel(String key) => key.split('/').skip(2).join('/');

  /// The Blocks tab: the engine's catalogue, one line per type.
  static List<PaletteEntryVm> _catalog(IList<NodeType> types) => [
    for (final t in types)
      PaletteEntryVm(
        id: 'type:${t.type}',
        title: t.type,
        tag: _sources.contains(t.type)
            ? 'IN'
            : (_sinks.contains(t.type) ? 'OUT' : 'FX'),
        group: t.category,
        detail: t.description.isEmpty ? null : t.description,
      ),
  ];

  /// The Tree tab: the points the tree has loaded, and the actions of the
  /// nodes whose detail it has read.
  List<PaletteEntryVm> _tree(String root, IMap<String, FlowBlock> blocks) {
    final used = {
      for (final x in blocks.values)
        if (pointOf(x) case final k?) _full(root, k),
    };
    return [
      for (final k in nodes.view)
        if (nodes.table[k] case final n? when n.type != null)
          PaletteEntryVm(
            id: 'key:$k',
            title: n.name,
            tag: AppIcon.typeTag(n.type),
            group: _group(k),
            detail: k.split('/').skip(2).join('/'),
            point: true,
            used: used.contains(k),
            value: switch (live.values[k]) {
              null => null,
              final v => valueText(
                v.value,
                choices: nodes.detail[k]?.choices.unlock ?? n.choices.unlock,
                unit: n.unit,
              ),
            },
          ),
      for (final MapEntry(key: k, value: det) in nodes.detail.entries)
        for (final a in det.actions)
          if (a.level != 'config' && a.group == null)
            PaletteEntryVm(
              id: 'act:$k/${a.name}',
              title: a.name,
              tag: 'ACT',
              group: _group('$k/x'),
              detail: k.split('/').skip(2).join('/'),
              point: true,
              action: true,
              used: used.contains(k),
              value: S.current.actionInputs(a.params.length),
            ),
    ];
  }

  /// The palette group of a tree point: the path of its parent below the
  /// site, without `downstream` (`modbus / tcp-tank`, `storage / tank`).
  static String _group(String key) {
    final parts = key.split('/').skip(2).toList();
    final path = parts.first == 'downstream' ? parts.skip(1) : parts;
    return path.take(path.length - 1).join(' / ');
  }

  /// The values of [b]'s fields: the watch's (only for a block the deployed
  /// version has, with the same type), else the tree's own value of the
  /// point a `subscribe` reads or a `set` writes.
  LiveValue? Function(String) _live(FlowBlock b, String root) {
    final dep = flowEditor.deployed?.blocks[b.id];
    final same = dep != null && dep.type == b.type;
    final point = pointOf(b);
    final tree = point == null || b.type == 'invoke'
        ? null
        : live.values[_full(root, point)];
    return (k) {
      final v = same ? flowEditor.ports[k] : null;
      if (v != null) {
        return v;
      }
      if (tree != null &&
          (k == portKey('out', b.id, 'out') && b.type != 'set' ||
              k == portKey('in', b.id, 'in') && b.type == 'set')) {
        return tree;
      }
      return null;
    };
  }

  FlowBlockVm _block(
    FlowBlock b,
    NodeType? t,
    List<FlowField> rows,
    FlowDraft d,
    String root,
    bool selected,
  ) {
    final role = roleOf(b.type);
    final writes = writingTypes.contains(b.type);
    final live = _live(b, root);
    final point = pointOf(b);
    final info = point == null ? null : nodes.table[_full(root, point)];
    final v = variadicOf(t, b);
    return FlowBlockVm(
      id: b.id,
      title: b.id,
      type: switch (role) {
        BlockRole.node => _connection(point, parent: true),
        BlockRole.action => _connection(point, parent: false),
        _ => b.type,
      },
      kind: switch (role) {
        BlockRole.node => BlockKindVm.node,
        BlockRole.logic => BlockKindVm.logic,
        BlockRole.sink => BlockKindVm.sink,
        BlockRole.action => BlockKindVm.action,
      },
      x: b.x,
      y: b.y,
      width: blockWidthOf(role),
      selected: selected,
      rows: [
        for (final f in rows)
          () {
            final value = fieldValue(
              b,
              f,
              d,
              live,
              unit: info?.unit,
              choices: info?.choices.unlock ?? const [],
            );
            return FieldRowVm(
              id: f.id,
              label: f.label,
              value: value.text,
              tone: value.bad
                  ? ValueTone.bad
                  : (value.bound ? ValueTone.bound : ValueTone.plain),
              inPort: f.inPort,
              outPort: f.outPort,
              inMark: f.inPort == null
                  ? PortMark.none
                  : (!value.bound
                        ? PortMark.free
                        : (writes ? PortMark.write : PortMark.bound)),
              outMark: f.outPort == null
                  ? PortMark.none
                  : (d.edges.any(
                          (e) => e.from == b.id && e.fromPort == f.outPort,
                        )
                        ? PortMark.bound
                        : PortMark.free),
            );
          }(),
      ],
      variadic: v == null
          ? null
          : VariadicVm(
              label: S.current.inputsCount(v.names.length),
              canRemove: v.names.length > v.min,
              addLabel: S.current.addInput,
              removeLabel: S.current.removeInput,
            ),
    );
  }

  /// `modbus/tcp-tank` of `downstream/modbus/tcp-tank/level` (the parent of a
  /// point, or a node itself), without `downstream`.
  static String _connection(String? key, {required bool parent}) {
    if (key == null) {
      return '';
    }
    var parts = key.split('/');
    if (parts.first == 'wy' && parts.length > 2) {
      parts = parts.skip(2).toList();
    }
    if (parts.first == 'downstream') {
      parts = parts.skip(1).toList();
    }
    if (parent && parts.length > 1) {
      parts = parts.take(parts.length - 1).toList();
    }
    return parts.join('/');
  }

  static String _kindLabel(BlockRole r) => switch (r) {
    BlockRole.node => S.current.kindTreeNode,
    BlockRole.logic => S.current.kindLogic,
    BlockRole.sink => S.current.kindSink,
    BlockRole.action => S.current.kindAction,
  };

  InspectorRowVm _inspectorRow(
    FlowBlock b,
    FlowField f,
    FlowDraft d,
    String root,
    String Function(String block, String port) labelOf,
  ) {
    final into = f.inPort == null
        ? null
        : d.edges
              .where((e) => e.to == b.id && e.toPort == f.inPort)
              .firstOrNull;
    final targets = [
      if (f.outPort != null)
        for (final e in d.edges)
          if (e.from == b.id && e.fromPort == f.outPort)
            '${e.to}.${_inLabel(e.toPort)}',
    ];
    final hint = f.spec?.description ?? '';
    if (into != null) {
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        editor: FieldEditorVm.bound,
        source: '${into.from}.${labelOf(into.from, into.fromPort)}',
        writes: writingTypes.contains(b.type),
        inPort: f.inPort,
        hint: hint,
      );
    }
    final p = f.spec;
    if (p != null) {
      final v = b.cfg[p.name] ?? p.defaultValue;
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        editor: p.choices.isNotEmpty
            ? FieldEditorVm.choice
            : (p.type == 'bool' ? FieldEditorVm.toggle : FieldEditorVm.text),
        value: switch (v) {
          null => '',
          final Map<Object?, Object?> m => flowJson(m),
          final List<Object?> l => flowJson(l),
          _ => '$v',
        },
        choices: p.choices.unlock,
        inPort: f.inPort,
        hint: hint,
      );
    }
    if (f.kind == FieldKind.arg) {
      final v = (b.cfg['args'] as Map?)?[f.label];
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        editor: FieldEditorVm.text,
        value: v == null ? '' : (v is String ? v : jsonEncode(v)),
      );
    }
    final value = fieldValue(b, f, d, _live(b, root)).text;
    if (f.kind == FieldKind.output) {
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        editor: FieldEditorVm.output,
        value: value,
        targets: targets.isEmpty
            ? S.current.notBound
            : '→ ${targets.join(', ')}',
      );
    }
    return InspectorRowVm(
      id: f.id,
      name: f.label,
      editor: FieldEditorVm.sample,
      value: value.isEmpty ? '—' : value,
      inPort: f.inPort,
    );
  }

  static String _inLabel(String port) =>
      port.startsWith('in.') ? port.substring(3) : port;

  /// The inspector with nothing selected (spec §6, proposed): the flow.
  FlowSummaryVm _summary(
    String root,
    String id,
    FlowDraft? d,
    IList<String> problems,
  ) {
    final own = live.values['$root/dataflows/$id'];
    final val = own?.value is Map
        ? own!.value! as Map
        : const <String, Object?>{};
    final known = flows.table[id];
    final by = val['deployed_by'] as String? ?? known?.deployedBy;
    final maxperm = switch (d?.rest['permissions']) {
      final Map<Object?, Object?> m => m['maxperm'] as String?,
      _ => null,
    };
    final keys = d == null ? null : flowKeysOf(d);
    final ids = d?.blocks.keys.toList() ?? const <String>[];
    return FlowSummaryVm(
      label: S.current.kindFlow,
      title: id.isEmpty ? S.current.newDataflow : id,
      facts: [
        (
          S.current.factVersion,
          flowEditor.version > 0
              ? '${flowEditor.version}'
              : S.current.notDeployed,
        ),
        if (by != null)
          (
            S.current.factDeployedBy,
            own == null ? by : '$by · ${_ago(own.time)}',
          ),
        if (maxperm != null) (S.current.factMayWrite, maxperm),
        if (flowEditor.watchRefused == 'permission_denied')
          (S.current.factLive, S.current.liveRefused),
        if (keys != null && keys.reads.isNotEmpty)
          (S.current.factReads, keys.reads.join(', ')),
        if (keys != null && keys.writes.isNotEmpty)
          (S.current.factWrites, keys.writes.join(', ')),
      ],
      problemsLabel: S.current.problems,
      problems: [
        for (final p in problems) ProblemVm(p, block: _blockIn(p, ids)),
      ],
    );
  }

  /// The block a problem names: the longest block id it holds as a word.
  static String? _blockIn(String problem, List<String> ids) {
    String? best;
    for (final id in ids) {
      final hit = RegExp(
        '(^|[^A-Za-z0-9_])${RegExp.escape(id)}([^A-Za-z0-9_]|\$)',
      ).hasMatch(problem);
      if (hit && (best == null || id.length > best.length)) {
        best = id;
      }
    }
    return best;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inMinutes < 1) {
      return S.current.agoNow;
    }
    if (d.inHours < 1) {
      return S.current.agoMinutes(d.inMinutes);
    }
    if (d.inDays < 1) {
      return S.current.agoHours(d.inHours);
    }
    return S.current.agoDays(d.inDays);
  }

  /// A typed text as the parameter's type: a number, a bool, JSON for a
  /// structure; text otherwise.
  static Object? _typed(String v, String type) {
    final s = v.trim();
    switch (type) {
      case 'number' || 'int':
        return num.tryParse(s) ?? v;
      case 'bool':
        return s == 'true' ? true : (s == 'false' ? false : v);
      case 'map' || 'array':
        try {
          return flowJsonDecode(v);
        } on FormatException {
          return v;
        }
      case 'dynamic':
        if (s.isEmpty) {
          return v;
        }
        try {
          return flowJsonDecode(s);
        } on FormatException {
          return v;
        }
      default:
        return v;
    }
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.watch,
    required this.flowLabel,
    required this.blockLabel,
    required this.state,
    required this.stateDot,
    required this.deployReason,
    required this.paletteTab,
    required this.palette,
    required this.blocks,
    required this.wires,
    required this.nameField,
    required this.inspectorKind,
    required this.inspectorTitle,
    required this.inspectorNote,
    required this.inspectorRows,
    required this.summary,
    required this.onDeploy,
    required this.onValidate,
    required this.onClose,
    required this.onPaletteTab,
    required this.onPick,
    required this.onDrop,
    required this.onClear,
    required this.onMove,
    required this.onSelect,
    required this.onBind,
    required this.onUnbind,
    required this.onDropEntry,
    required this.onResize,
    required this.onFieldChanged,
    required this.onFieldUnbind,
    required this.onFieldBind,
    required this.onProblem,
    required this.onRemove,
    required this.onLogo,
  }) : super(
         equals: [
           watch,
           flowLabel,
           blockLabel,
           state,
           stateDot,
           deployReason,
           paletteTab,
           palette,
           blocks,
           wires,
           nameField,
           inspectorKind,
           inspectorTitle,
           inspectorNote,
           inspectorRows,
           summary,
           onRemove != null,
         ],
       );

  /// What the editor subscribes to (Tree tab parents, block points, the
  /// flow's `~val`).
  final List<String> watch;
  final String flowLabel;
  final String? blockLabel;
  final String state;
  final bool stateDot;
  final String? deployReason;
  final String paletteTab;
  final List<PaletteEntryVm> palette;
  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final ParamFieldVm? nameField;
  final String inspectorKind;
  final String inspectorTitle;
  final String inspectorNote;
  final List<InspectorRowVm> inspectorRows;
  final FlowSummaryVm? summary;
  final VoidCallback onDeploy;
  final VoidCallback onValidate;
  final VoidCallback onClose;
  final ValueChanged<String> onPaletteTab;
  final ValueChanged<String> onPick;
  final void Function(String entry, double x, double y) onDrop;
  final VoidCallback onClear;
  final void Function(String id, double x, double y) onMove;
  final ValueChanged<String> onSelect;
  final void Function(FieldRefVm from, String block, String toPort) onBind;
  final void Function(String block, String rowId) onUnbind;
  final void Function(String entry, String block, String toPort) onDropEntry;
  final void Function(String block, {required bool add}) onResize;
  final void Function(String id, String value) onFieldChanged;
  final ValueChanged<String> onFieldUnbind;
  final void Function(String id, FieldRefVm from) onFieldBind;
  final ValueChanged<String> onProblem;
  final VoidCallback? onRemove;

  final void Function() onLogo;
}
