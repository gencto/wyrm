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
import 'package:business/redux/flow_editor/actions/move_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/new_flow_action.dart';
import 'package:business/redux/flow_editor/actions/paste_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/preview_flow_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_edge_action.dart';
import 'package:business/redux/flow_editor/actions/redo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/select_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_form_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_clipboard_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/set_operand_value_action.dart';
import 'package:business/redux/flow_editor/actions/set_palette_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/set_viewed_field_action.dart';
import 'package:business/redux/flow_editor/actions/undo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/flow_editor/actions/watch_flow_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/shell/window_bar.dart';

import '../common/side_panels.dart';
import '../common/value_viewer.dart';
import '../common/window.dart';
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

/// A value with no time: what the definition says a field holds.
final _typedTime = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

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
      // The draft runs as a preview while it differs from the deployed
      // version (debounced by the service).
      if (before.run != now.run) {
        store.dispatchSync(PreviewFlowAction());
      }
    },
    onDispose: (store) => store
      ..dispatchSync(UnwatchKeysAction(_watch(store.state, id)))
      ..dispatchSync(WatchFlowAction(null))
      ..dispatchSync(PreviewFlowAction(stop: true)),
    builder: (context, vm) => FlowEditorPage(
      window: vm.window,
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
        onBind: vm.onBind,
        onRebind: vm.onRebind,
        onUnbind: vm.onUnbind,
        onDropEntry: vm.onDropEntry,
        onResize: vm.onResize,
        refusal: vm.refusal,
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
      onGoToSource: vm.onProblem,
      unbindLabel: S.current.unbind,
      goToSourceLabel: S.current.goToSource,
      boundLabel: S.current.boundMark,
      removeLabel: S.current.removeBlock,
      onRemove: vm.onRemove,
      onLogo: vm.onLogo,
      panels: vm.panelWidths,
      onPanelWidth: vm.onPanelWidth,
      viewer: vm.viewer,
      onView: vm.onView,
      onCloseViewer: vm.onCloseViewer,
      viewLabel: S.current.viewValue,
      copyLabel: S.current.copyValue,
      copiedLabel: S.current.copiedValue,
      closeLabel: S.current.closeLabel,
      onSelectMany: vm.onSelectMany,
      onCommand: vm.onCommand,
      menu: vm.menu,
      onPin: vm.onPin,
      onViewField: vm.onViewField,
      onFieldPin: vm.onFieldPin,
      pinLabel: S.current.pinField,
      unpinLabel: S.current.unpinField,
      pinLockedLabel: S.current.pinLocked,
      onSaveViewer: vm.onSaveViewer,
      validateViewer: vm.validateViewer,
      editLabel: S.current.viewerEdit,
      saveLabel: S.current.viewerSave,
      cancelLabel: S.current.cancel,
      saveHint: S.current.viewerSaveHint(
        flowOnMac ? 'Cmd+Enter' : 'Ctrl+Enter',
      ),
      deployAskTitle: S.current.deployAskTitle,
      deployAskMessage: S.current.deployAskMessage(vm.flowLabel),
    ),
  );

  Future<void> _open(Store<AppState> store) async {
    final isNew = id == newFlowId;
    await store.dispatchAndWait(LoadFlowAction(isNew ? '' : id, isNew: isNew));
    // The deployed version's live values (ADR 0038 §3); a draft that
    // differs from it runs as a preview (`dataflows` ▸ `preview`).
    store
      ..dispatchSync(WatchFlowAction(isNew ? null : id))
      ..dispatchSync(PreviewFlowAction());
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
      // What the deployed publish blocks last published: their inputs.
      if (id != newFlowId)
        for (final b in ed.deployed?.blocks.values ?? const <FlowBlock>[])
          ?_published(root, id, b),
    }.toList();
  }
}

/// The value a `publish` block of flow [flow] publishes
/// (`dataflows/<flow>/nodes/<node>`), null for any other block.
String? _published(String root, String flow, FlowBlock b) =>
    switch (b.cfg['node']) {
      final String n when b.type == 'publish' && flow.isNotEmpty =>
        '$root/dataflows/$flow/nodes/$n',
      _ => null,
    };

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
    final run = d == null ? null : previewDefOf(d);
    final previewing = _previewing;
    final fields = {
      for (final x in blocks.values)
        x.id: fieldsOf(types[x.type], x, edges: edges),
    };
    // Rows a block draws: its pinned fields (spec §12): the user's choice,
    // else the type's default, and always a field a wire touches.
    final rows = {
      for (final x in blocks.values)
        x.id: [
          for (final f in fields[x.id]!)
            if (fieldPinned(x, f, edges)) f,
        ],
    };
    final selection = ed.selection;
    // The field the viewer shows: its block and its field.
    final viewed = switch (ed.viewedField?.split('/')) {
      [final vb, ...final rest] when blocks[vb] != null => (
        blocks[vb]!,
        fields[vb]!.where((f) => f.id == rest.join('/')).firstOrNull,
      ),
      _ => null,
    };
    LiveValue? Function(String) look(FlowBlock x) =>
        _live(x, root, fields, previewing: previewing);
    String inLabelOf(String block, String port) =>
        fields[block]?.where((f) => f.inPort == port).firstOrNull?.label ??
        port;

    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      watch: FlowEditorPageConnector._watch(state, connector.id),
      run: run,
      flowLabel: id.isNotEmpty ? id : S.current.newDataflow,
      blockLabel:
          sel ??
          (selection.length > 1 ? S.current.fmBlocks(selection.length) : null),
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
          _block(
            x,
            types[x.type],
            rows[x.id]!,
            d!,
            look(x),
            selection.contains(x.id),
            previewing: previewing,
          ),
      ],
      wires: [
        for (final e in edges)
          () {
            final writes = writingTypes.contains(blocks[e.to]?.type);
            // A parameter's echo and a variable's value send at start: into
            // a device they write at every deploy (ADR 0038 §6,
            // `blocks.rs`).
            final fromParam =
                fields[e.from]
                    ?.where((f) => f.sends(e.fromPort))
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
              warningNote: S.current.firesAtStartNote,
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
              if (formOf(b, edges) case final form?)
                InspectorRowVm(
                  id: 'form',
                  name: S.current.blockForm,
                  editor: FieldEditorVm.choice,
                  value: form.label,
                  choices: [for (final f in formsOf(b.type)) f.label],
                ),
              for (final f in fields[b.id]!)
                _inspectorRow(b, f, d!, look(b), inLabelOf).pin(
                  pinned: fieldPinned(b, f, edges),
                  locked: fieldBound(b, f, edges),
                ),
            ],
      summary: b == null
          ? _summary(root, id, d, problems, previewing: previewing)
          : null,
      viewer: switch (ed.viewedField?.split('/')) {
        // The Form row: the form's name.
        [final vb, 'form'] when blocks[vb] != null => switch (formOf(
          blocks[vb]!,
          edges,
        )) {
          final form? => valueViewerOf(title: '$vb.form', value: form.label),
          null => null,
        },
        [final vb, ...final rest] when d != null && blocks[vb] != null =>
          _viewer(
            blocks[vb]!,
            fields[vb]!.where((f) => f.id == rest.join('/')).firstOrNull,
            d,
            look(blocks[vb]!),
          ),
        _ => null,
      },
      onView: (row) {
        if (sel != null) {
          dispatchSync(SetViewedFieldAction('$sel/$row'));
        }
      },
      onCloseViewer: () => dispatchSync(SetViewedFieldAction(null)),
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
      onMove: (to, {required nudge}) => dispatchSync(
        MoveBlocksAction({
          for (final MapEntry(:key, :value) in to.entries)
            key: (value.dx, value.dy),
        }, tag: nudge ? 'nudge' : null),
      ),
      onSelect: (x) => dispatchSync(SetSelectedBlockAction(x)),
      onSelectMany: (ids, {required add, required toggle}) =>
          dispatchSync(SelectBlocksAction(ids, add: add, toggle: toggle)),
      onCommand: _command,
      menu: (ids, block, row) => _menu(ids, block, row, fields),
      onPin: (block, field, {required pinned}) =>
          dispatchSync(SetFieldPinAction(block, field, pinned: pinned)),
      onFieldPin: (field, {required pinned}) {
        if (sel != null) {
          dispatchSync(SetFieldPinAction(sel, field, pinned: pinned));
        }
      },
      onViewField: (block, row) =>
          dispatchSync(SetViewedFieldAction('$block/$row')),
      onSaveViewer: (text) {
        if (viewed case (final vb, final f?)) {
          _setField(vb, f, text);
        }
      },
      validateViewer: (text) {
        final edit = switch (viewed) {
          (final vb, final f?) => fieldEditOf(vb, f, edges).edit,
          _ => null,
        };
        return switch (edit == null ? null : fieldEditError(text, edit)) {
          null => null,
          FieldEditError.number => S.current.viewerBadNumber,
          FieldEditError.json => S.current.viewerBadJson,
          FieldEditError.toggle => S.current.viewerBadBool,
        };
      },
      onBind: (from, to, port) =>
          dispatchSync(ConnectPortsAction(from.block, from.port, to, port)),
      onUnbind: _unbind,
      onRebind: (oldBlock, oldPort, block, port) {
        final old = fields[oldBlock]
            ?.where((f) => f.inPort == oldPort)
            .firstOrNull;
        dispatchSync(
          RebindEdgeAction(
            oldBlock,
            oldPort,
            block,
            port,
            param: old?.spec?.name,
            keep: old != null && old.typed
                ? _shown[portKey('in', oldBlock, oldPort)]?.value
                : null,
          ),
        );
      },
      refusal: (from, block, row, {replacing}) {
        final to = fields[block]?.where((f) => f.id == row).firstOrNull;
        if (d == null || to == null) {
          return null;
        }
        final r = bindRefusal(
          types,
          d,
          fromBlock: from.block,
          fromPort: from.port,
          toBlock: block,
          to: to,
          replacing: replacing,
        );
        return switch (r?.reason) {
          null => null,
          BindRefusal.output => S.current.refuseOutput,
          BindRefusal.noInput => S.current.refuseNoInput(to.label),
          BindRefusal.self => S.current.refuseSelf,
          BindRefusal.type => S.current.refuseType(r!.from, r.to),
          BindRefusal.loop => S.current.refuseLoop,
        };
      },
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
        if (row == 'form') {
          final form = formsOf(
            b.type,
          ).where((f) => f.label == text).firstOrNull;
          if (form != null) {
            dispatchSync(SetBlockFormAction(b.id, form.id));
          }
          return;
        }
        final f = fields[b.id]!.where((x) => x.id == row).firstOrNull;
        if (f != null) {
          _setField(b, f, text);
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
      onRemove: sel == null
          ? null
          : () => dispatchSync(RemoveBlocksAction([sel])),
      onLogo: () => dispatch(GoAction.navigate(const ExplorerRoute())),
      panelWidths: WorkspacePanels.flowEditor.widths(panels.widths),
      onPanelWidth: (side, w) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.flowEditor.slot(side), w),
      ),
    );
  }

  /// Types [text] into field [f] of block [b]: what the inspector's row
  /// and the value viewer's Save both do (spec §15). The field's kind reads
  /// the text (a number, a bool, JSON; `fieldEditOf`, `typedText`); a
  /// parameter goes into the config, an operand into `values`, an
  /// argument into `args`. A field that is not typed (bound, an output)
  /// changes nothing.
  void _setField(FlowBlock b, FlowField f, String text) {
    final edit = fieldEditOf(
      b,
      f,
      flowEditor.draft?.edges ?? const IListConst<FlowEdge>([]),
    ).edit;
    if (edit == null) {
      return;
    }
    final value = typedText(text, edit);
    if (f.operand) {
      dispatchSync(SetOperandValueAction(b.id, f.inPort!, value));
    } else if (f.kind == FieldKind.arg) {
      final args = Map<String, Object?>.of(
        (b.cfg['args'] as Map?)?.cast<String, Object?>() ?? const {},
      );
      args[f.name] = value;
      dispatchSync(SetBlockParamAction(b.id, 'args', args));
    } else if (f.spec case final p?) {
      dispatchSync(SetBlockParamAction(b.id, p.name, value));
    }
  }

  /// A command of the canvas, from a key or from its context menu (spec
  /// §13). The state is read when the command comes: the clipboard and
  /// the history change without the page being rebuilt.
  void _command(FlowCommand command, {Offset? at}) {
    final ed = SelectFlowEditor(currentState());
    final d = ed.draft;
    if (d == null) {
      return;
    }
    final ids = ed.selection.unlock;
    switch (command) {
      case .copy:
        _copy(d, ids);
      case .cut:
        if (_copy(d, ids)) {
          dispatchSync(RemoveBlocksAction(ids));
        }
      case .paste:
        unawaited(_paste(at));
      case .duplicate:
        final picked = [
          for (final b in d.blocks.values)
            if (ids.contains(b.id)) b,
        ];
        if (picked.isNotEmpty) {
          // Beside the originals, one grid step down and to the right.
          dispatchSync(
            PasteBlocksAction(
              clipTextOf(d, ids),
              picked.map((b) => b.x).reduce((a, b) => a < b ? a : b) + 20,
              picked.map((b) => b.y).reduce((a, b) => a < b ? a : b) + 20,
            ),
          );
        }
      case .delete:
        dispatchSync(RemoveBlocksAction(ids));
      case .undo:
        dispatchSync(UndoFlowAction());
      case .redo:
        dispatchSync(RedoFlowAction());
      case .escape:
        // The viewer first, then the selection.
        if (ed.viewedField != null) {
          dispatchSync(SetViewedFieldAction(null));
        } else {
          dispatchSync(SetSelectedBlockAction(null));
        }
      // The canvas and the page answer the rest; custom blocks wait for
      // the engine (ADR 0040).
      case .selectAll ||
          .marquee ||
          .addToSelection ||
          .moveSelection ||
          .nudgeLeft ||
          .nudgeRight ||
          .nudgeUp ||
          .nudgeDown ||
          .unbind ||
          .pan ||
          .zoom ||
          .zoomIn ||
          .zoomOut ||
          .zoomReset ||
          .zoomFit ||
          .viewValue ||
          .searchPalette ||
          .deploy ||
          .help ||
          .fields ||
          .unpin ||
          .createCustomBlock ||
          .editCustomBlock:
        break;
    }
  }

  /// Copies the blocks [ids]: into the editor's own clipboard (it lasts
  /// from one flow to the next) and, as the same JSON, onto the system's
  /// (another window pastes it). False when there is nothing to copy.
  bool _copy(FlowDraft d, Set<String> ids) {
    final text = clipTextOf(d, ids);
    if (text == null) {
      return false;
    }
    dispatchSync(SetClipboardAction(text));
    unawaited(_systemCopy(text));
    return true;
  }

  static Future<void> _systemCopy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Object {
      // No system clipboard here: the editor's own still pastes.
    }
  }

  /// Pastes at [at] what the system clipboard holds; a text that is not
  /// blocks pastes nothing. Only where there is no system clipboard (or it
  /// is empty) the editor's own copy is pasted.
  Future<void> _paste(Offset? at) async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      text = null;
    }
    final own = SelectFlowEditor(currentState()).clipboard;
    dispatchSync(
      PasteBlocksAction(
        text == null || text.isEmpty ? own : text,
        at?.dx ?? 60,
        at?.dy ?? 60,
      ),
    );
  }

  /// The context menu (spec §13) opened on [block] (and its [row]) with the
  /// selection [ids], or on the empty canvas.
  FlowMenuVm _menu(
    Set<String> ids,
    String? block,
    String? row,
    Map<String, List<FlowField>> fields,
  ) {
    final ed = SelectFlowEditor(currentState());
    final d = ed.draft;
    final b = block == null ? null : d?.blocks[block];
    final edges = d?.edges ?? const IListConst<FlowEdge>([]);
    final none = ids.isEmpty ? S.current.fmNothingSelected : null;
    final one = ids.length == 1 && b != null;
    FlowPinVm pinOf(FlowField f) => FlowPinVm(
      id: f.id,
      label: f.label,
      pinned: fieldPinned(b!, f, edges),
      lockedReason: fieldBound(b, f, edges) ? S.current.fmBound : null,
    );
    final own = one ? fields[b.id] ?? const <FlowField>[] : const <FlowField>[];
    final onRow = row == null
        ? null
        : own.where((f) => f.id == row).firstOrNull;
    return FlowMenuVm(
      title: one
          ? b.id
          : (ids.length > 1
                ? S.current.fmBlocks(ids.length)
                : (d == null || d.id.isEmpty ? S.current.fmCanvas : d.id)),
      subtitle: one
          ? b.type
          : (ids.length > 1 ? '' : S.current.fmBlocks(d?.blocks.length ?? 0)),
      fields: [for (final f in own) pinOf(f)],
      unpin: onRow == null ? null : pinOf(onRow),
      items: [
        FlowMenuItemVm(.cut, disabledReason: none),
        FlowMenuItemVm(.copy, disabledReason: none),
        const FlowMenuItemVm(.paste),
        FlowMenuItemVm(.duplicate, disabledReason: none),
        FlowMenuItemVm(.delete, disabledReason: none, danger: ids.isNotEmpty),
        const FlowMenuItemVm(.selectAll, divider: true),
        if (ids.isEmpty) ...[
          FlowMenuItemVm(
            .undo,
            divider: true,
            disabledReason: ed.undo.isEmpty ? S.current.fmNothingToUndo : null,
          ),
          FlowMenuItemVm(
            .redo,
            disabledReason: ed.redo.isEmpty ? S.current.fmNothingToRedo : null,
          ),
        ],
        if (one) ...[
          const FlowMenuItemVm(.fields, divider: true),
          if (onRow != null) const FlowMenuItemVm(.unpin),
        ],
        // Custom blocks wait for sub-flows in the engine (ADR 0040); the
        // cut of a selection into one is ready (`extractSubflow`).
        if (ids.isNotEmpty)
          FlowMenuItemVm(
            .createCustomBlock,
            divider: true,
            disabledReason: S.current.fmNeedsEngine,
          ),
        if (one)
          FlowMenuItemVm(
            .editCustomBlock,
            disabledReason: S.current.fmNeedsEngine,
          ),
      ],
    );
  }

  /// Whether the draft's values come from its preview: it runs otherwise
  /// than the deployed version (its layout aside), the broker has a
  /// preview, and the preview has answered (until then the watch's values
  /// stay, so the first edit does not blank every field).
  bool get _previewing {
    final ed = flowEditor;
    final d = ed.draft;
    final dep = ed.deployed;
    return d != null &&
        ed.previewOff == null &&
        (ed.previewPorts.isNotEmpty ||
            ed.previewSinks.isNotEmpty ||
            ed.previewError != null) &&
        (dep == null || previewDefOf(dep) != previewDefOf(d));
  }

  /// The live values the blocks show now: the preview's or the watch's.
  IMap<String, LiveValue> get _shown =>
      _previewing ? flowEditor.previewPorts : flowEditor.ports;

  /// Unbinds the field [row] of [block]; a typed parameter keeps the last
  /// value it had.
  void _unbind(String block, String row) {
    final d = flowEditor.draft;
    final b = d?.blocks[block];
    if (b == null) {
      return;
    }
    final t = flowEditor.types.where((t) => t.type == b.type).firstOrNull;
    final f = fieldsOf(
      t,
      b,
      edges: d!.edges,
    ).where((x) => x.id == row).firstOrNull;
    final port = f?.inPort;
    if (f == null || port == null) {
      return;
    }
    final last = _shown[portKey('in', block, port)]?.value;
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
                for (final p in action.params) p.name: ?p.defaultValue,
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

  /// The values of [b]'s fields, by key of [portKey].
  ///
  /// While the draft runs as a preview ([previewing]) every block reads the
  /// preview's values; else a block the deployed version has unchanged
  /// reads the watch's, and the point a `subscribe` reads or a `set` writes
  /// its tree value.
  ///
  /// The engine records a port only from its first sample after the watch
  /// or the preview opened (ADR 0038 §6), so a slow point or a value sent
  /// once at start shows nothing there. What such a field holds is still
  /// known, and is shown: an input bound by a wire of the draft holds the
  /// value of its source field; a field's echo (a variable's `Value`, a
  /// parameter) what comes into it, else its typed value; an input's echo
  /// what came in.
  LiveValue? Function(String) _live(
    FlowBlock b,
    String root,
    Map<String, List<FlowField>> fields, {
    required bool previewing,
    int hops = 0,
  }) {
    final ed = flowEditor;
    final d = ed.draft;
    final dep = ed.deployed?.blocks[b.id];
    final same = dep != null && dep.type == b.type && sameCfg(dep.cfg, b.cfg);
    final ports = previewing ? ed.previewPorts : (same ? ed.ports : null);
    final point = pointOf(b);
    final flow = d?.id ?? '';
    final pub = previewing || !same ? null : _published(root, flow, b);
    final tree = pub != null
        ? live.values[pub]
        : (point == null || b.type == 'invoke'
              ? null
              : live.values[_full(root, point)]);
    final inPrefix = portKey('in', b.id, '');
    final outPrefix = portKey('out', b.id, '');
    LiveValue? look(String k) {
      final v = ports?[k];
      if (v != null) {
        return v;
      }
      if (tree != null &&
          (k == portKey('out', b.id, 'out') && b.type != 'set' ||
              k == portKey('in', b.id, 'in') &&
                  (b.type == 'set' || b.type == 'publish'))) {
        return tree;
      }
      if (d == null || hops > 6) {
        return null;
      }
      if (k.startsWith(inPrefix)) {
        final port = k.substring(inPrefix.length);
        final wire = d.edges
            .where((e) => e.to == b.id && e.toPort == port)
            .firstOrNull;
        final src = wire == null ? null : d.blocks[wire.from];
        if (wire == null || src == null) {
          // An unbound operand holds its typed constant (ADR 0038 §7).
          final f = fields[b.id]
              ?.where((f) => f.operand && f.inPort == port)
              .firstOrNull;
          final constant = f == null ? null : operandValueOf(b, port);
          return constant == null
              ? null
              : LiveValue(time: _typedTime, value: constant);
        }
        return _live(
          src,
          root,
          fields,
          previewing: previewing,
          hops: hops + 1,
        )(portKey('out', src.id, wire.fromPort));
      }
      if (!k.startsWith(outPrefix)) {
        return null;
      }
      final port = k.substring(outPrefix.length);
      if (!previewing && same) {
        // An output wired straight into a publish block sent what that
        // block last published.
        for (final e in ed.deployed?.edges ?? const IListConst<FlowEdge>([])) {
          final to = ed.deployed?.blocks[e.to];
          final key = to == null ? null : _published(root, flow, to);
          if (e.from == b.id && e.fromPort == port && key != null) {
            if (live.values[key] case final v?) {
              return v;
            }
          }
        }
      }
      final f = fields[b.id]
          ?.where((f) => f.sends(port) && f.kind != FieldKind.output)
          .firstOrNull;
      if (f == null) {
        return null;
      }
      final inPort = f.inPort;
      if (inPort != null &&
          d.edges.any((e) => e.to == b.id && e.toPort == inPort)) {
        return look(portKey('in', b.id, inPort));
      }
      if (f.kind == FieldKind.input) {
        return inPort == null ? null : look(portKey('in', b.id, inPort));
      }
      if (ports?[portKey('param', b.id, f.name)] case final v?) {
        return v;
      }
      final typed = b.cfg[f.name] ?? f.spec?.defaultValue;
      return typed == null ? null : LiveValue(time: _typedTime, value: typed);
    }

    return look;
  }

  FlowBlockVm _block(
    FlowBlock b,
    NodeType? t,
    List<FlowField> rows,
    FlowDraft d,
    LiveValue? Function(String) live,
    bool selected, {
    required bool previewing,
  }) {
    final role = roleOf(b.type);
    final writes = writingTypes.contains(b.type);
    final root = site.root ?? '';
    final point = pointOf(b);
    // What a sink would write in the preview (nothing is written).
    final ghost = previewing && _sinks.contains(b.type)
        ? flowEditor.previewSinks[b.id]
        : null;
    // The draft no longer runs: the preview's last values, greyed.
    final stale = previewing && flowEditor.previewError != null;
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
      tag: ghost == null ? null : S.current.previewTag,
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
            final wouldDo = ghost != null && f.inPort == 'in'
                ? (b.type == 'invoke'
                      ? S.current.wouldRun(valueText(ghost.value))
                      : S.current.wouldWrite(
                          valueText(
                            ghost.value,
                            unit: info?.unit,
                            choices: info?.choices.unlock ?? const [],
                          ),
                        ))
                : null;
            return FieldRowVm(
              id: f.id,
              label: f.label,
              name: f.name,
              value: wouldDo ?? value.text,
              tone: switch (value) {
                _ when wouldDo != null => ValueTone.ghost,
                FieldValue(bad: true) => ValueTone.bad,
                FieldValue(live: true) when stale => ValueTone.stale,
                FieldValue(bound: true) => ValueTone.bound,
                _ => ValueTone.plain,
              },
              inPort: f.inPort,
              outPort: f.outPort,
              outAliases: f.outAliases,
              inMark: f.inPort == null
                  ? PortMark.none
                  : (!value.bound
                        ? PortMark.free
                        : (writes ? PortMark.write : PortMark.bound)),
              outMark: f.outPort == null
                  ? PortMark.none
                  : (d.edges.any((e) => e.from == b.id && f.sends(e.fromPort))
                        ? PortMark.bound
                        : PortMark.free),
            );
          }(),
      ],
      variadic: v == null
          ? null
          : (v.step == 2
                ? VariadicVm(
                    label: S.current.pairsCount(v.names.length ~/ 2),
                    canRemove: v.removes.isNotEmpty,
                    addLabel: S.current.addPair,
                    removeLabel: S.current.removePair,
                  )
                : VariadicVm(
                    label: S.current.inputsCount(v.names.length),
                    canRemove: v.removes.isNotEmpty,
                    addLabel: S.current.addInput,
                    removeLabel: S.current.removeInput,
                  )),
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

  /// The viewer of field [f] of block [b], live (owner request
  /// 2026-11-09): titled `<block>.<engine name>`, the value [fieldValue]
  /// shows, whole; null when the field is gone.
  ValueViewerVm? _viewer(
    FlowBlock b,
    FlowField? f,
    FlowDraft d,
    LiveValue? Function(String) live,
  ) {
    if (f == null) {
      return null;
    }
    final point = pointOf(b);
    final info = point == null
        ? null
        : nodes.table[_full(site.root ?? '', point)];
    final at = f.kind == FieldKind.input || f.kind == FieldKind.output;
    final v = fieldValue(b, f, d, live);
    final how = fieldEditOf(b, f, d.edges);
    final text = fieldEditText(b, f);
    return valueViewerOf(
      title: '${b.id}.${f.name}',
      value: v.raw,
      known: v.raw != null || v.live,
      unit: at ? info?.unit : null,
      choices: at ? info?.choices.unlock ?? const [] : const [],
      quality: switch (v.quality) {
        final q? => qualityMarkOf(q),
        null => null,
      },
    ).typed(
      edit: switch (how.edit) {
        null => null,
        FieldEdit.choice => ViewerEditVm(
          kind: .choice,
          text: text,
          choices: f.spec?.choices.unlock ?? const [],
        ),
        FieldEdit.toggle => ViewerEditVm(
          kind: .toggle,
          text: text == 'true' ? 'true' : 'false',
        ),
        FieldEdit.number => ViewerEditVm(kind: .number, text: text),
        FieldEdit.json => ViewerEditVm(kind: .json, text: text),
        FieldEdit.text || FieldEdit.any => ViewerEditVm(
          kind: .text,
          text: text,
        ),
      },
      locked: switch (how.locked) {
        null => null,
        FieldLocked.bound => S.current.viewerLockedBound,
        FieldLocked.output => S.current.viewerLockedOutput,
        FieldLocked.input => S.current.viewerLockedInput,
      },
    );
  }

  InspectorRowVm _inspectorRow(
    FlowBlock b,
    FlowField f,
    FlowDraft d,
    LiveValue? Function(String) live,
    String Function(String block, String port) inLabelOf,
  ) {
    final into = f.inPort == null
        ? null
        : d.edges
              .where((e) => e.to == b.id && e.toPort == f.inPort)
              .firstOrNull;
    final targets = [
      if (f.outPort != null)
        for (final e in d.edges)
          if (e.from == b.id && f.sends(e.fromPort))
            '${e.to}.${inLabelOf(e.to, e.toPort)}',
    ];
    final hint = f.spec?.description ?? '';
    if (into != null) {
      // The value that comes in, not where it comes from (owner decision
      // 2026-11-08): the wire shows the source, `Go to source` selects it.
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.bound,
        value: fieldValue(b, f, d, live).text,
        sourceBlock: into.from,
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
        engine: f.name == f.label ? '' : f.name,
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
      final v = (b.cfg['args'] as Map?)?[f.name];
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.text,
        value: v == null ? '' : (v is String ? v : jsonEncode(v)),
      );
    }
    if (f.operand) {
      // An operand holds a typed constant until a binding replaces it.
      final v = operandValueOf(b, f.inPort!);
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.text,
        value: switch (v) {
          null => '',
          final String s => s,
          _ => jsonEncode(v),
        },
        inPort: f.inPort,
      );
    }
    final value = fieldValue(b, f, d, live).text;
    if (f.kind == FieldKind.output) {
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
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

  /// The inspector with nothing selected (spec §6, proposed): the flow.
  FlowSummaryVm _summary(
    String root,
    String id,
    FlowDraft? d,
    IList<String> problems, {
    required bool previewing,
  }) {
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
        if (d != null && (previewing || flowEditor.deployed != null))
          (
            S.current.factValues,
            previewing ? S.current.valuesPreview : S.current.valuesDeployed,
          ),
        if (flowEditor.watchRefused == 'permission_denied' ||
            flowEditor.previewOff == 'permission_denied')
          (S.current.factLive, S.current.liveRefused),
        if (keys != null && keys.reads.isNotEmpty)
          (S.current.factReads, keys.reads.join(', ')),
        if (keys != null && keys.writes.isNotEmpty)
          (S.current.factWrites, keys.writes.join(', ')),
      ],
      problemsLabel: S.current.problems,
      problems: [
        // The broker's compiler refused the draft's preview.
        if (flowEditor.previewError case final m? when previewing)
          ProblemVm(S.current.previewInvalid(m), block: _blockIn(m, ids)),
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
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.window,
    required this.watch,
    required this.run,
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
    required this.onRebind,
    required this.refusal,
    required this.onDropEntry,
    required this.onResize,
    required this.onFieldChanged,
    required this.onFieldUnbind,
    required this.onFieldBind,
    required this.onProblem,
    required this.onRemove,
    required this.onLogo,
    required this.panelWidths,
    required this.onPanelWidth,
    required this.viewer,
    required this.onView,
    required this.onCloseViewer,
    required this.onSelectMany,
    required this.onCommand,
    required this.menu,
    required this.onPin,
    required this.onFieldPin,
    required this.onViewField,
    required this.onSaveViewer,
    required this.validateViewer,
  }) : super(
         equals: [
           window,
           watch,
           run,
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
           panelWidths,
           viewer,
         ],
       );

  /// The frameless window's side of the top bar.
  final WindowBarVm window;

  /// What the editor subscribes to (Tree tab parents, block points, the
  /// flow's `~val`).
  final List<String> watch;

  /// What the draft runs as (its definition, layout aside): a change runs
  /// it again as a preview.
  final Object? run;
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
  final void Function(Map<String, Offset> to, {required bool nudge}) onMove;
  final ValueChanged<String> onSelect;
  final void Function(
    Set<String> ids, {
    required bool add,
    required bool toggle,
  })
  onSelectMany;
  final void Function(FlowCommand command, {Offset? at}) onCommand;
  final FlowMenuVm Function(Set<String> ids, String? block, String? row) menu;
  final void Function(String block, String field, {required bool pinned}) onPin;
  final void Function(String field, {required bool pinned}) onFieldPin;
  final void Function(String block, String row) onViewField;
  final ValueChanged<String> onSaveViewer;
  final String? Function(String text) validateViewer;
  final void Function(FieldRefVm from, String block, String toPort) onBind;
  final void Function(String block, String rowId) onUnbind;
  final void Function(
    String oldBlock,
    String oldPort,
    String block,
    String toPort,
  )
  onRebind;
  final String? Function(
    FieldRefVm from,
    String block,
    String rowId, {
    (String, String)? replacing,
  })
  refusal;
  final void Function(String entry, String block, String toPort) onDropEntry;
  final void Function(String block, {required bool add}) onResize;
  final void Function(String id, String value) onFieldChanged;
  final ValueChanged<String> onFieldUnbind;
  final void Function(String id, FieldRefVm from) onFieldBind;
  final ValueChanged<String> onProblem;
  final VoidCallback? onRemove;

  final void Function() onLogo;
  final SidePanelWidths panelWidths;
  final void Function(PanelSide side, double width) onPanelWidth;

  /// The open viewer of a field (`flowEditor.viewedField`), live.
  final ValueViewerVm? viewer;
  final ValueChanged<String> onView;
  final VoidCallback onCloseViewer;
}
