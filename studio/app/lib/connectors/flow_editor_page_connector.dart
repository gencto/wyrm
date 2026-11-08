import 'dart:async';

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
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_palette_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_edge.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/pages/flow_editor_page.dart';

import '../common/forms.dart';
import '../navigation/go_action.dart';
import 'flows_page_connector.dart';

/// Block types that read from the tree (IN, teal) and that write to it
/// (OUT, ember); everything between is logic (FX).
const _sources = {'subscribe', 'liveliness', 'timer', 'history', 'dql'};
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
      // What the first view-model watches; later changes are diffed below.
      store.dispatchSync(WatchKeysAction(_treeWatch(store.state)));
      unawaited(_open(store));
    },
    onWillChange: (context, store, before, now) {
      // The Tree tab shows the live values of its points.
      if (!listEquals(before.watch, now.watch)) {
        store
          ..dispatchSync(WatchKeysAction(now.watch))
          ..dispatchSync(UnwatchKeysAction(before.watch));
      }
    },
    onDispose: (store) => store
      ..dispatchSync(UnwatchKeysAction(_watch(store.state, id)))
      ..dispatchSync(UnwatchKeysAction(_treeWatch(store.state))),
    builder: (context, vm) => FlowEditorPage(
      crumbs: vm.crumbs,
      status: vm.status,
      statusTone: vm.statusTone,
      validateLabel: S.current.validate,
      deployLabel: S.current.deploy,
      deployReason: vm.deployReason,
      onDeploy: vm.onDeploy,
      onValidate: vm.onValidate,
      onClose: vm.onClose,
      paletteTabs: [
        TabItemVm(id: 'blocks', label: S.current.paletteBlocks),
        TabItemVm(id: 'tree', label: S.current.paletteTree),
      ],
      paletteTab: vm.paletteTab,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.palette,
      searchHint: S.current.searchLinks,
      onPick: vm.onPick,
      blocks: vm.blocks,
      wires: vm.wires,
      onSelect: vm.onSelect,
      onMove: vm.onMove,
      onConnect: vm.onConnect,
      onDisconnect: vm.onDisconnect,
      onDrop: vm.onDrop,
      nameField: vm.nameField,
      propertiesTitle: S.current.block,
      propertiesNote: S.current.flowPropertiesNote,
      selectedTitle: vm.selectedTitle,
      selectedType: vm.selectedType,
      selectedDescription: vm.selectedDescription,
      fields: vm.fields,
      bindings: vm.bindings,
      onRemove: vm.onRemove,
      removeLabel: S.current.removeBlock,
    ),
  );

  Future<void> _open(Store<AppState> store) async {
    final isNew = id == newFlowId;
    await store.dispatchAndWait(LoadFlowAction(isNew ? '' : id, isNew: isNew));
    store.dispatchSync(WatchKeysAction(_watch(store.state, id)));
    await store.dispatchAndWait(ValidateFlowAction());
  }

  /// The parents of the Tree tab's points, while it is shown.
  static List<String> _treeWatch(AppState s) {
    if (SelectFlowEditor(s).palette != 'tree') {
      return const [];
    }
    final nodes = SelectNodes(s);
    return {
      for (final k in nodes.view)
        if (nodes.table[k]?.type != null)
          '${k.substring(0, k.lastIndexOf('/'))}/*',
    }.toList();
  }

  static List<String> _watch(AppState s, String id) {
    final root = SelectSite(s).root;
    return [if (root != null && id != newFlowId) '$root/dataflows/$id/nodes/*'];
  }
}

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
    final t = b == null ? null : types[b.type];
    final wiredIn = {
      for (final e in d?.edges ?? const IListConst<FlowEdge>([]))
        '${e.to}.${e.toPort}',
    };
    final wiredOut = {
      for (final e in d?.edges ?? const IListConst<FlowEdge>([]))
        '${e.from}.${e.fromPort}',
    };
    final problems = ed.problems;
    final busy =
        ed.version >= 0 && state.wait.isWaitingForType<DeployFlowAction>();
    return _Vm(
      watch: FlowEditorPageConnector._treeWatch(state),
      crumbs: [
        S.current.wsFlows,
        if (id.isNotEmpty) id else S.current.newDataflow,
        ?sel,
      ],
      status: switch (ed) {
        _ when d == null => S.current.loading,
        _ when busy => S.current.deploying,
        _ when problems.isNotEmpty => problems.first,
        _ when ed.message != null && !ed.dirty => ed.message!,
        _ when ed.dirty => S.current.draftValid,
        _ => S.current.flowVersion(ed.version),
      },
      statusTone: problems.isNotEmpty
          ? Tone.bad
          : (ed.dirty ? Tone.ember : Tone.good),
      deployReason: d == null
          ? S.current.loading
          : (problems.isNotEmpty
                ? S.current.fixFirst
                : (!ed.dirty && !isNew
                      ? S.current.nothingToDeploy
                      : site.needs('config', '$root/dataflows'))),
      paletteTab: ed.palette,
      palette: ed.palette == 'tree'
          ? [
              for (final k in nodes.view)
                if (nodes.table[k] case final n? when n.type != null)
                  PaletteEntryVm(
                    id: 'key:$k',
                    title: n.name,
                    tag: AppIcon.typeTag(n.type),
                    group: _group(k),
                    detail: k.split('/').skip(2).join('/'),
                    point: true,
                    value: switch (live.values[k]) {
                      null => null,
                      final v => valueText(
                        v.value,
                        choices:
                            nodes.detail[k]?.choices.unlock ?? n.choices.unlock,
                        unit: n.unit,
                      ),
                    },
                  ),
            ]
          : [
              for (final t in ed.types)
                PaletteEntryVm(
                  id: 'type:${t.type}',
                  title: t.type,
                  tag: _tag(t.type),
                  group: t.category,
                  detail: t.description.isEmpty ? null : t.description,
                ),
            ],
      blocks: [
        for (final blk in d?.blocks.values ?? const <FlowBlock>[])
          _block(
            blk,
            types[blk.type],
            blk.id == sel,
            wiredIn,
            wiredOut,
            root,
            id,
          ),
      ],
      wires: [
        for (final e in d?.edges ?? const IListConst<FlowEdge>([]))
          FlowWireVm(e.from, e.fromPort, e.to, e.toPort),
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
      selectedTitle: b?.id,
      selectedType: b?.type,
      selectedDescription: t?.description,
      fields: [
        if (b != null)
          for (final p in t?.params ?? const IListConst<ParamSpec>([]))
            () {
              final f = paramField(p);
              final v = b.cfg[p.name];
              return ParamFieldVm(
                id: '${b.id}.${p.name}',
                label: f.label,
                kind: f.kind == ParamKind.file ? ParamKind.text : f.kind,
                value: v is Map || v is List ? flowJson(v) : v,
                choices: f.choices,
                required: f.required,
                hint: f.hint,
                description: f.description,
                onChanged: (x) => dispatchSync(
                  SetBlockParamAction(b.id, p.name, _parse(x, p.type)),
                ),
              );
            }(),
      ],
      bindings: [
        if (b != null)
          for (final e in d?.edges ?? const IListConst<FlowEdge>([]))
            if (e.to == b.id) (e.toPort, '${e.from}.${e.fromPort}'),
      ],
      onDeploy: () => unawaited(dispatchAndWait(DeployFlowAction())),
      onValidate: () => unawaited(dispatchAndWait(ValidateFlowAction())),
      onClose: () => dispatch(GoAction.pop()),
      onPaletteTab: (t) => dispatchSync(SetPaletteAction(t)),
      onPick: (entry) => _add(
        entry,
        60 + 30.0 * ((d?.blocks.length ?? 0) % 8),
        60 + 30.0 * ((d?.blocks.length ?? 0) % 8),
      ),
      onDrop: _add,
      onSelect: (b) => dispatchSync(SetSelectedBlockAction(b)),
      onMove: (b, x, y) => dispatchSync(MoveBlockAction(b, x, y)),
      onConnect: (a, ap, b, bp) =>
          dispatchSync(ConnectPortsAction(a, ap, b, bp)),
      onDisconnect: (b, bp) => dispatchSync(DisconnectEdgeAction(b, bp)),
      onRemove: sel == null ? null : () => dispatchSync(RemoveBlockAction(sel)),
    );
  }

  void _add(String entry, double x, double y) {
    if (entry.startsWith('type:')) {
      dispatchSync(AddBlockAction(entry.substring(5), x, y));
    } else if (entry.startsWith('key:')) {
      final key = entry.substring(4);
      final rel = key.split('/').skip(2).join('/');
      dispatchSync(AddBlockAction('subscribe', x, y, cfg: {'key': rel}));
    }
  }

  /// The palette group of a tree point: the path of its parent below the
  /// site, without `downstream` (`modbus / tcp-tank`, `storage / tank`).
  static String _group(String key) {
    final parts = key.split('/').skip(2).toList();
    final path = parts.first == 'downstream' ? parts.skip(1) : parts;
    return path.take(path.length - 1).join(' / ');
  }

  static String _tag(String type) =>
      _sources.contains(type) ? 'IN' : (_sinks.contains(type) ? 'OUT' : 'FX');

  FlowBlockVm _block(
    FlowBlock b,
    NodeType? t,
    bool selected,
    Set<String> wiredIn,
    Set<String> wiredOut,
    String root,
    String flow,
  ) {
    final ports = portsOf(t, b);
    String shown(String port) {
      final name = port.startsWith('in.') ? port.substring(3) : port;
      final v = b.cfg[name];
      return v == null ? '' : (v is Map || v is List ? '…' : '$v');
    }

    final live = live_(root, flow, b.id);
    return FlowBlockVm(
      id: b.id,
      title: b.id,
      subtitle: b.type,
      tag: _tag(b.type),
      tone: _sources.contains(b.type)
          ? Tone.good
          : (_sinks.contains(b.type) ? Tone.ember : Tone.neutral),
      x: b.x,
      y: b.y,
      selected: selected,
      inputs: [
        for (final p in ports.inputs)
          PortVm(
            name: p,
            value: shown(p),
            wired: wiredIn.contains('${b.id}.$p'),
          ),
        if (b.cfg['key'] case final String k when ports.inputs.isEmpty)
          PortVm(name: 'key', value: k),
      ],
      outputs: [
        for (final p in ports.outputs)
          PortVm(name: p, wired: wiredOut.contains('${b.id}.$p')),
      ],
      footer: live,
    );
  }

  /// The block's last value, when the engine publishes one
  /// (`dataflows/<id>/nodes/<block>`).
  String? live_(String root, String flow, String block) {
    final v = live.values['$root/dataflows/$flow/nodes/$block'];
    return v == null ? null : '${valueText(v.value)} · ${v.quality.name}';
  }

  static Object? _parse(Object? v, String type) {
    if (v is! String) {
      return v;
    }
    if (type == 'map' || type == 'array' || type == 'dynamic') {
      try {
        return flowJsonDecode(v);
      } on FormatException {
        return v;
      }
    }
    return v;
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.watch,
    required this.crumbs,
    required this.status,
    required this.statusTone,
    required this.deployReason,
    required this.paletteTab,
    required this.palette,
    required this.blocks,
    required this.wires,
    required this.nameField,
    required this.selectedTitle,
    required this.selectedType,
    required this.selectedDescription,
    required this.fields,
    required this.bindings,
    required this.onDeploy,
    required this.onValidate,
    required this.onClose,
    required this.onPaletteTab,
    required this.onPick,
    required this.onDrop,
    required this.onSelect,
    required this.onMove,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRemove,
  }) : super(
         equals: [
           watch,
           crumbs,
           status,
           statusTone,
           deployReason,
           paletteTab,
           palette,
           blocks,
           wires,
           nameField,
           selectedTitle,
           selectedType,
           selectedDescription,
           fields,
           bindings,
           onRemove != null,
         ],
       );

  /// What the Tree tab subscribes to (`<parent>/*` of its points).
  final List<String> watch;
  final List<String> crumbs;
  final String status;
  final Tone statusTone;
  final String? deployReason;
  final String paletteTab;
  final List<PaletteEntryVm> palette;
  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final ParamFieldVm? nameField;
  final String? selectedTitle;
  final String? selectedType;
  final String? selectedDescription;
  final List<ParamFieldVm> fields;
  final List<(String, String)> bindings;
  final VoidCallback onDeploy;
  final VoidCallback onValidate;
  final VoidCallback onClose;
  final ValueChanged<String> onPaletteTab;
  final ValueChanged<String> onPick;
  final void Function(String entry, double x, double y) onDrop;
  final ValueChanged<String?> onSelect;
  final void Function(String id, double x, double y) onMove;
  final void Function(String a, String ap, String b, String bp) onConnect;
  final void Function(String to, String toPort) onDisconnect;
  final VoidCallback? onRemove;
}
