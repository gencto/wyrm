import 'dart:async';
import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/flow_editor/actions/add_block_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/create_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/disconnect_edge_action.dart';
import 'package:business/redux/flow_editor/actions/enter_block_action.dart';
import 'package:business/redux/flow_editor/actions/leave_block_action.dart';
import 'package:business/redux/flow_editor/actions/load_flow_action.dart';
import 'package:business/redux/flow_editor/actions/move_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/new_flow_action.dart';
import 'package:business/redux/flow_editor/actions/paste_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/place_library_block_action.dart';
import 'package:business/redux/flow_editor/actions/preview_flow_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_edge_action.dart';
import 'package:business/redux/flow_editor/actions/redo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/remove_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/remove_library_block_action.dart';
import 'package:business/redux/flow_editor/actions/rename_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/resize_block_ports_action.dart';
import 'package:business/redux/flow_editor/actions/resize_inputs_action.dart';
import 'package:business/redux/flow_editor/actions/retrieve_block_library_action.dart';
import 'package:business/redux/flow_editor/actions/save_block_to_library_action.dart';
import 'package:business/redux/flow_editor/actions/select_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_form_action.dart';
import 'package:business/redux/flow_editor/actions/set_block_param_action.dart';
import 'package:business/redux/flow_editor/actions/set_clipboard_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/set_operand_value_action.dart';
import 'package:business/redux/flow_editor/actions/set_palette_action.dart';
import 'package:business/redux/flow_editor/actions/set_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/set_tree_query_action.dart';
import 'package:business/redux/flow_editor/actions/set_viewed_field_action.dart';
import 'package:business/redux/flow_editor/actions/trigger_block_action.dart';
import 'package:business/redux/flow_editor/actions/undo_flow_action.dart';
import 'package:business/redux/flow_editor/actions/update_block_from_library_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/flow_editor/actions/watch_flow_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/nodes/actions/retrieve_details_action.dart';
import 'package:business/redux/nodes/actions/retrieve_nodes_action.dart';
import 'package:business/redux/nodes/actions/toggle_node_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/labels.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:business/wyrm/mappers/value_text.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:models/action_info.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/param_spec.dart';
import 'package:ui/buttons/segmented_tabs.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_legend.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/rows_editor.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/trees/tree_row.dart';

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
  'load_value',
  'list_children',
  'load_history',
  'get_node',
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
      // What the actions of the flow's action blocks take (their
      // arguments' types): read once per node, quietly.
      if (!listEquals(before.details, now.details) && now.details.isNotEmpty) {
        unawaited(store.dispatchAndWait(RetrieveDetailsAction(now.details)));
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
          disabledReason: vm.myBlocksOff,
        ),
        TabItemVm(id: 'tree', label: S.current.paletteTree),
      ],
      tree: vm.tree,
      onTreeToggle: vm.onTreeToggle,
      onTreeQuery: vm.onTreeQuery,
      onPaletteMenu: vm.onPaletteMenu,
      paletteEmpty: switch (vm.paletteTab) {
        'my' => S.current.myBlocksEmpty,
        'tree' => S.current.treeEmpty,
        _ => '',
      },
      writable: vm.writable,
      readLabel: S.current.dropRead,
      writeLabel: S.current.dropWrite,
      crumbs: vm.crumbs,
      onBack: vm.onBack,
      backLabel: S.current.flowBack,
      insideNote: vm.insideNote,
      createBlock: vm.createBlock,
      validateBlock: vm.validateBlock,
      onCreateBlock: vm.onCreateBlock,
      onRenameBlock: vm.onRenameBlock,
      validateBlockName: vm.validateBlockName,
      renameTitle: S.current.mbRename,
      renameLabel: S.current.mbRename,
      prompt: vm.prompt,
      onPromptSave: vm.onPromptSave,
      onPromptCancel: vm.onPromptCancel,
      validatePrompt: vm.validatePrompt,
      onRun: vm.onRun,
      inspectorLinks: [
        if (vm.openInside case final label?) (label, vm.onOpenInside),
      ],
      confirmLabel: S.current.turnOn,
      paletteTab: vm.paletteTab,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.palette,
      searchHint: vm.paletteTab == 'tree'
          ? S.current.findInTree
          : S.current.findBlock,
      paletteNotes: vm.paletteTab == 'tree'
          ? [
              PaletteNoteVm(S.current.treePoint, S.current.treePointNote2),
              PaletteNoteVm(
                S.current.treeAction,
                S.current.treeActionNote2,
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
        onOpen: vm.onOpen,
        onRowAction: vm.onRowAction,
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
      suggestLabel: S.current.suggestPick,
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
    // The Tree tab draws the site's live tree: its lists open like the
    // Explorer's.
    if (SelectNodes(store.state).expanded.isEmpty) {
      unawaited(store.dispatchAndWait(RetrieveNodesAction(quiet: true)));
    }
    // Custom blocks: whether this broker has them, and the site's library.
    unawaited(store.dispatchAndWait(RetrieveBlockLibraryAction()));
    final details = _details(store.state);
    if (details.isNotEmpty) {
      unawaited(store.dispatchAndWait(RetrieveDetailsAction(details)));
    }
    await store.dispatchAndWait(ValidateFlowAction());
  }

  /// The nodes whose actions the flow's `invoke` blocks run and whose
  /// `~meta` is not read yet: it says what each argument is.
  static List<String> _details(AppState s) {
    final root = SelectSite(s).root;
    final d = SelectFlowEditor(s).draft;
    if (root == null || d == null) {
      return const [];
    }
    final read = SelectNodes(s).detail;
    return {
      for (final b in d.blocks.values)
        if (b.type == 'invoke')
          if (pointOf(b) case final k? when !read.containsKey(_full(root, k)))
            _full(root, k),
    }.toList();
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
      // The values of the leaves the Tree tab shows: every open node's.
      if (ed.palette == 'tree')
        for (final k in nodes.expanded)
          if (_treeSections.any((s) => k.startsWith('$root/$s'))) '$k/*',
      for (final b in ed.draft?.blocks.values ?? const <FlowBlock>[])
        if (_pointTypes.contains(b.type))
          if (pointOf(b) case final k?) _full(root, k),
      if (id != newFlowId) '$root/dataflows/$id',
      // What the deployed publish blocks last published: their inputs.
      if (id != newFlowId)
        for (final b in ed.deployed?.blocks.values ?? const <FlowBlock>[])
          ?_published(root, id, b),
    }.toList();
  }
}

/// The sections of a site the Tree tab shows: what a flow may read and
/// write (spec 06 step 9).
const _treeSections = ['downstream', 'dataflows', 'storage'];

/// The block types that stand for one point of the tree: its value is
/// theirs.
const _pointTypes = {'subscribe', 'liveliness', 'set', 'publish'};

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
    // What the canvas shows: the flow, or the inside of a custom block.
    final d = ed.draft;
    // The flow itself, with every inside view folded back into it: what
    // validate, preview and deploy read.
    final flow = ed.root;
    final frames = ed.frames;
    final inside = frames.isNotEmpty;
    final caps = ed.caps;
    final types = {for (final t in ed.allTypes) t.type: t};
    final isNew = connector.id == newFlowId;
    final id = flow?.id ?? '';
    final sel = ed.selectedBlock;
    final b = sel == null ? null : d?.blocks[sel];
    final deployed = ed.deployed;
    final differs =
        flow != null &&
        (deployed == null || defOf(flow, 0) != defOf(deployed, 0));
    final problems = ed.problems;
    final busy = state.wait.isWaitingForType<DeployFlowAction>();
    final edges = d?.edges ?? const IListConst<FlowEdge>([]);
    final blocks = d?.blocks ?? const IMapConst<String, FlowBlock>({});
    final run = flow == null ? null : previewDefOf(flow);
    final previewing = _previewing;
    final fields = {
      for (final x in blocks.values)
        x.id: fieldsOf(
          types[x.type],
          x,
          edges: edges,
          actionParams: _actionParams(root, x),
        ),
    };
    final defs = blockDefsOf(d);
    final keyedSel = b == null ? null : scopedKeyOf(types[b.type]);
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
        _live(x, root, fields, previewing: previewing, differs: differs);
    String inLabelOf(String block, String port) =>
        fields[block]?.where((f) => f.inPort == port).firstOrNull?.label ??
        port;

    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      watch: FlowEditorPageConnector._watch(state, connector.id),
      details: FlowEditorPageConnector._details(state),
      run: run,
      crumbs: [for (final f in frames) f.block],
      insideNote: inside && flow != null
          ? S.current.instancesInFlow(instancesOf(flow, frames.last.block))
          : null,
      onBack: (levels) => dispatchSync(LeaveBlockAction(levels: levels)),
      myBlocksOff: caps.blocks ? null : S.current.myBlocksOff,
      tree: ed.palette == 'tree' ? _treeRows(root, blocks) : null,
      writable: ed.palette == 'tree' ? _writable(root) : const {},
      onTreeToggle: (key) {
        final opening = !nodes.expanded.contains(key);
        dispatchSync(ToggleNodeAction(key));
        // A node's actions are in its own `~meta`: read once, when it is
        // first opened here (the tree's lists do not carry them).
        if (opening && !nodes.detail.containsKey(key)) {
          unawaited(dispatchAndWait(RetrieveDetailsAction([key])));
        }
      },
      onTreeQuery: (q) => dispatchSync(SetTreeQueryAction(q)),
      onPaletteMenu: (entry, item) {
        final name = entry.substring(entry.lastIndexOf(':') + 1);
        switch (item) {
          case 'edit':
            dispatchSync(EnterBlockAction(name));
          case 'save':
            unawaited(dispatchAndWait(SaveBlockToLibraryAction(name)));
          case 'update':
            unawaited(dispatchAndWait(UpdateBlockFromLibraryAction(name)));
          case 'delete':
            dispatchSync(RemoveCustomBlockAction(name));
          case 'remove-library':
            unawaited(dispatchAndWait(RemoveLibraryBlockAction(name)));
        }
      },
      onRenameBlock: (entry, name) => dispatchSync(
        RenameCustomBlockAction(
          entry.substring(entry.lastIndexOf(':') + 1),
          name,
        ),
      ),
      validateBlockName: (name) => !blockNameOk(name)
          ? S.current.cbBadName
          : (defs.containsKey(name) ? S.current.cbTaken : null),
      createBlock: _createBlock,
      validateBlock: (r) {
        final now = SelectFlowEditor(currentState()).draft;
        return switch (now == null
            ? null
            : customBlockProblem(now, _specOf(r))) {
          null => null,
          BlockNameProblem.name => S.current.cbBadName,
          BlockNameProblem.taken => S.current.cbTaken,
          BlockNameProblem.port => S.current.cbBadPort,
          BlockNameProblem.duplicate => S.current.cbDuplicate,
          BlockNameProblem.limit => S.current.cbLimit,
        };
      },
      onCreateBlock: (r) {
        final ids = SelectFlowEditor(currentState()).selection.unlock;
        dispatchSync(CreateCustomBlockAction(ids, _specOf(r)));
      },
      prompt: _prompt(root, blocks, types, rows),
      onPromptSave: (scope) {
        final block = ed.scopePrompt ?? '';
        final keyed = scopedKeyOf(types[blocks[block]?.type]);
        if (keyed != null) {
          dispatchSync(SetBlockParamAction(block, keyed.scope, scope));
        }
        dispatchSync(SetScopePromptAction(null));
      },
      onPromptCancel: () {
        // No scope, no binding: a key from a wire without one does not
        // compile. A block that has its scope keeps both.
        final x = blocks[ed.scopePrompt ?? ''];
        final keyed = scopedKeyOf(types[x?.type]);
        if (x != null && keyed != null && _blank(x.cfg[keyed.scope])) {
          dispatchSync(DisconnectEdgeAction(x.id, keyed.port));
        }
        dispatchSync(SetScopePromptAction(null));
      },
      validatePrompt: (scope) => _scopeError(root, scope),
      onRowAction: (block, row) {
        final keyed = scopedKeyOf(types[blocks[block]?.type]);
        if (keyed != null && row == 'p:${keyed.scope}') {
          dispatchSync(SetScopePromptAction(block));
        }
      },
      onOpen: (block) {
        if (blockNameOf(blocks[block]?.type ?? '') case final name?) {
          dispatchSync(EnterBlockAction(name, instance: block));
        }
      },
      onRun: (row) {
        final node = b == null ? null : _engineId(b.id);
        if (row == 'in:trigger' && node != null) {
          unawaited(dispatchAndWait(TriggerBlockAction(node)));
        }
      },
      openInside: b != null && caps.blocks && isInstance(b.type)
          ? S.current.openInside
          : null,
      onOpenInside: () {
        if (blockNameOf(b?.type ?? '') case final name?) {
          dispatchSync(EnterBlockAction(name, instance: b!.id));
        }
      },
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
          : inside
          ? S.current.deployInside
          : (!differs && !isNew
                ? S.current.nothingToDeploy
                : (problems.isNotEmpty
                      ? S.current.fixFirst
                      : site.needs('config', '$root/dataflows'))),
      paletteTab: ed.palette,
      palette: switch (ed.palette) {
        'tree' => const [],
        'my' => _myBlocks(root, flow, defs),
        _ => _catalog(ed.types),
      },
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
            final writes =
                writingTypes.contains(blocks[e.to]?.type) &&
                e.to != blockOutputsId;
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
              // Only `in` acts on a value sent at start; a trigger, an
              // argument and a behaviour never do (ADR 0040 §2).
              warning: writes && fromParam && e.toPort == 'in'
                  ? S.current.firesAtDeploy
                  : null,
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
      inspectorKind: b == null
          ? ''
          : (isBoundary(b.id)
                ? S.current.kindBlockPorts
                : _kindLabel(roleOf(b.type))),
      inspectorTitle: switch (b?.id) {
        null => '',
        blockInputsId => S.current.blockInputs,
        blockOutputsId => S.current.blockOutputs,
        final x => x,
      },
      inspectorNote: switch (b) {
        null => '',
        _ when b.id == blockInputsId => S.current.noteBlockInputs,
        _ when b.id == blockOutputsId => S.current.noteBlockOutputs,
        _ when roleOf(b.type) == BlockRole.node => S.current.noteTreeNode,
        _ when roleOf(b.type) == BlockRole.action =>
          behavesOf(types[b.type])
              ? S.current.noteActionBlock
              : S.current.noteAction,
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
                _inspectorRow(
                      b,
                      f,
                      d!,
                      look(b),
                      inLabelOf,
                      types[b.type],
                      root: root,
                      keyed: keyedSel,
                      runReason: _runReason(
                        b,
                        root,
                        caps,
                        differs: differs,
                        isNew: isNew,
                      ),
                    )
                    .pin(
                      pinned: fieldPinned(b, f, edges),
                      locked: fieldBound(b, f, edges),
                    )
                    .inGroup(_groupLabel(groupOf(types[b.type], b, f))),
            ],
      summary: b == null
          ? _summary(root, id, flow, problems, previewing: previewing)
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
        if (t != 'my' || caps.blocks) {
          dispatchSync(SetPaletteAction(t));
        }
        if (t == 'my') {
          unawaited(dispatchAndWait(RetrieveBlockLibraryAction()));
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
          BindRefusal.needsBroker => S.current.refuseNeedsBroker(to.label),
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
            cfg: {'key': relativeKey(entry.substring(4))},
            into: (block, port),
          ),
        );
      },
      onResize: (block, {required add}) => dispatchSync(
        isBoundary(block)
            ? ResizeBlockPortsAction(input: block == blockInputsId, add: add)
            : ResizeInputsAction(block, add: add),
      ),
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
        final f = b == null
            ? null
            : fields[b.id]!.where((x) => x.id == row).firstOrNull;
        final port = f?.inPort;
        if (b != null && f != null && port != null && from.block != b.id) {
          // An argument the action has and the block not yet: its key
          // first, so the port exists.
          if (f.kind == FieldKind.arg && !_args(b).containsKey(f.name)) {
            dispatchSync(
              SetBlockParamAction(b.id, 'args', {..._args(b), f.name: null}),
            );
          }
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
    if (b.id == blockInputsId) {
      // The default of a custom block's input.
      final defaults = {
        ...switch (b.cfg['defaults']) {
          final Map<Object?, Object?> m => m.cast<String, Object?>(),
          _ => const <String, Object?>{},
        },
      };
      if (text.trim().isEmpty) {
        defaults.remove(f.name);
      } else {
        defaults[f.name] = value;
      }
      dispatchSync(SetBlockParamAction(b.id, 'defaults', defaults));
    } else if (f.operand) {
      dispatchSync(SetOperandValueAction(b.id, f.inPort!, value));
    } else if (f.kind == FieldKind.arg) {
      final args = _args(b);
      // Nothing typed: an argument the action may go without leaves the
      // call; any other is sent as nothing.
      if (text.trim().isEmpty && f.argSpec != null && !f.argSpec!.required) {
        args.remove(f.name);
      } else {
        args[f.name] = text.trim().isEmpty ? null : value;
      }
      // An empty map stays a map: the block still names its arguments.
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
      case .editCustomBlock:
        final one = ids.length == 1 ? d.blocks[ids.single] : null;
        if (blockNameOf(one?.type ?? '') case final name?) {
          dispatchSync(EnterBlockAction(name, instance: one!.id));
        }
      // The canvas and the page answer the rest (the page asks the name
      // of a new custom block first).
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
          .createCustomBlock:
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
    final real = {
      for (final id in ids)
        if (!isBoundary(id)) id,
    };
    final none = real.isEmpty ? S.current.fmNothingSelected : null;
    final one = ids.length == 1 && b != null;
    final noBlocks = ed.caps.blocks ? null : S.current.fmNeedsBroker;
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
        // Custom blocks (ADR 0040 §3): a selection becomes one; an
        // instance opens its inside. Off, with the reason, on a broker
        // without them.
        if (ids.isNotEmpty)
          FlowMenuItemVm(
            .createCustomBlock,
            divider: true,
            disabledReason: noBlocks ?? none,
          ),
        if (one)
          FlowMenuItemVm(
            .editCustomBlock,
            disabledReason:
                noBlocks ?? (isInstance(b.type) ? null : S.current.fmNotCustom),
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
    final d = ed.root;
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
      return;
    }
    if (entry.startsWith('lib:')) {
      // A block of the site's library: the flow copies it first.
      unawaited(
        dispatchAndWait(PlaceLibraryBlockAction(entry.substring(4), x, y)),
      );
      return;
    }
    // A point (read or write) or an action of the tree (flow-editor.md
    // §18).
    final full = entry.substring(entry.indexOf(':') + 1);
    final i = full.lastIndexOf('/');
    final action = entry.startsWith('act:') && i > 0
        ? nodes.detail[full.substring(0, i)]?.actions
              .where((a) => a.name == full.substring(i + 1))
              .firstOrNull
        : null;
    final made = blockOfEntry(entry, action: action, caps: flowEditor.caps);
    if (made != null) {
      dispatchSync(
        AddBlockAction(made.type, x, y, cfg: made.cfg, pins: made.pins),
      );
    }
  }

  /// The arguments of an `invoke` block, as its config holds them.
  static Map<String, Object?> _args(FlowBlock b) => {
    ...switch (b.cfg['args']) {
      final Map<Object?, Object?> m => m.cast<String, Object?>(),
      _ => const <String, Object?>{},
    },
  };

  static bool _blank(Object? v) => v is! String || v.trim().isEmpty;

  /// The parameters of the action an `invoke` block runs, from its node's
  /// `~meta` (read once, `nodes.detail`); none while it is not read.
  Iterable<ParamSpec> _actionParams(String root, FlowBlock b) {
    if (b.type != 'invoke') {
      return const [];
    }
    final path = pointOf(b);
    final name = b.cfg['action'];
    return path == null
        ? const []
        : nodes.detail[_full(root, path)]?.actions
                  .where((a) => a.name == name)
                  .firstOrNull
                  ?.params ??
              const [];
  }

  /// The id the engine knows block [id] of the canvas by: its own in the
  /// flow, `<instance>/<inner>` inside a custom block. Null inside a
  /// block opened from the palette: no instance, so no running node.
  String? _engineId(String id) {
    final path = insidePath(flowEditor.frames);
    return path == null ? null : (path.isEmpty ? id : '$path/$id');
  }

  /// Why `Run` is off for [b], or null when it runs: the engine's
  /// `trigger` acts on the deployed flow, so the draft must be it.
  String? _runReason(
    FlowBlock b,
    String root,
    FlowCaps caps, {
    required bool differs,
    required bool isNew,
  }) {
    final flow = flowEditor.flowId ?? '';
    if (!caps.trigger) {
      return S.current.runNoBroker;
    }
    if (isNew || flowEditor.deployed == null) {
      return S.current.runNotDeployed;
    }
    if (differs) {
      return S.current.runDraft;
    }
    if (_engineId(b.id) == null) {
      return S.current.runNoInstance;
    }
    if (b.cfg['enabled'] == false) {
      return S.current.runOff;
    }
    return site.needs('write', '$root/dataflows/$flow');
  }

  static String _groupLabel(FieldGroup g) => switch (g) {
    FieldGroup.none => '',
    FieldGroup.target => S.current.grpTarget,
    FieldGroup.arguments => S.current.grpArguments,
    FieldGroup.behaviour => S.current.grpBehaviour,
    FieldGroup.events => S.current.grpEvents,
    FieldGroup.state => S.current.grpState,
  };

  /// What is wrong with a scope typed for a key of this site, in words.
  String? _scopeError(String root, String scope) => switch (scopeProblem(
    scope,
    site: root.startsWith('wy/') ? root.substring(3) : root,
  )) {
    null => null,
    ScopeProblem.empty => S.current.scopeEmpty,
    ScopeProblem.section => S.current.scopeSection,
    ScopeProblem.otherSite => S.current.scopeOtherSite,
    ScopeProblem.segment => S.current.scopeSegment,
  };

  /// The scope prompt of the block `flowEditor.scopePrompt` (spec §17): on
  /// its `Scope` row when it is one, else on its key's.
  ScopePromptVm? _prompt(
    String root,
    IMap<String, FlowBlock> blocks,
    Map<String, NodeType> types,
    Map<String, List<FlowField>> rows,
  ) {
    final b = blocks[flowEditor.scopePrompt ?? ''];
    final keyed = scopedKeyOf(types[b?.type]);
    if (b == null || keyed == null) {
      return null;
    }
    final site = root.startsWith('wy/') ? root.substring(3) : root;
    final own = b.cfg[keyed.scope];
    final suggested = scopeSuggestion(b.cfg[keyed.key] as String?, site: site);
    final onBlock = rows[b.id]?.any((f) => f.id == 'p:${keyed.scope}') ?? false;
    return ScopePromptVm(
      block: b.id,
      row: 'p:${onBlock ? keyed.scope : keyed.key}',
      title: S.current.scopeTitle,
      note: S.current.scopeNote,
      value: _blank(own) ? suggested : own! as String,
      suggestions: {
        suggested,
        for (final s in scopeSections) '$s/**',
      }.toList(),
      saveLabel: S.current.viewerSave,
      cancelLabel: S.current.cancel,
    );
  }

  /// What `Create custom block…` asks: a free name, and the ports the
  /// selection would have, each with what it is wired to outside.
  CustomBlockDialogVm? _createBlock() {
    final ed = SelectFlowEditor(currentState());
    final d = ed.draft;
    final ids = {
      for (final id in ed.selection)
        if (!isBoundary(id)) id,
    };
    if (d == null || ids.isEmpty || !ed.caps.blocks) {
      return null;
    }
    final sub = extractSubflow(d, ids);
    final defs = blockDefsOf(d);
    var n = 1;
    while (defs.containsKey('block$n')) {
      n++;
    }
    return CustomBlockDialogVm(
      title: S.current.cbTitle,
      note: S.current.cbNote(sub.blocks.length),
      name: 'block$n',
      inputs: [
        for (final p in sub.inputs)
          BlockPortVm(
            name: p.name,
            detail: '← ${p.outside.first.$1}.${p.outside.first.$2}',
          ),
      ],
      outputs: [
        for (final p in sub.outputs)
          BlockPortVm(
            name: p.name,
            detail: [
              '→',
              [for (final o in p.outside) '${o.$1}.${o.$2}'].join(', '),
            ].join(' '),
          ),
      ],
      nameLabel: S.current.cbName,
      descriptionLabel: S.current.cbDescription,
      inputsLabel: S.current.cbInputs,
      outputsLabel: S.current.cbOutputs,
      defaultHint: S.current.cbDefault,
      noPorts: S.current.cbNone,
      createLabel: S.current.cbCreate,
      cancelLabel: S.current.cancel,
    );
  }

  /// What the dialog handed back as the block to make: a default is read
  /// as JSON when it parses (`2` is a number, `AHU-` a text).
  static CustomBlockSpec _specOf(CustomBlockResult r) => CustomBlockSpec(
    name: r.name,
    description: r.description,
    inputs: r.inputs,
    outputs: r.outputs,
    defaults: {
      for (final e in r.defaults.entries)
        e.key: typedText(e.value, FieldEdit.any),
    },
  );

  /// The My blocks tab (spec §20): the custom blocks of this flow, then
  /// the site's library. Each is dragged onto the canvas; its menu saves,
  /// renames, deletes or updates it.
  List<PaletteEntryVm> _myBlocks(
    String root,
    FlowDraft? flow,
    Map<String, Map<String, Object?>> defs,
  ) {
    final inside = flowEditor.frames.isNotEmpty;
    final config = site.needs('config', '$root/dataflows');
    final library = {for (final l in flowEditor.library) l.name: l};
    final back = inside ? S.current.mbBackFirst : null;
    return [
      for (final MapEntry(key: name, value: def) in defs.entries)
        () {
          final used = flow == null ? 0 : instancesOf(flow, name);
          final lib = library[name];
          final copied = libraryVersionOf(def);
          return PaletteEntryVm(
            id: 'type:$blockTypePrefix$name',
            title: name,
            tag: 'MY',
            group: S.current.myBlocksThisFlow,
            detail: def['description'] as String?,
            value: lib != null && lib.version != copied
                ? S.current.mbUpdateTo(lib.version)
                : S.current.mbUsed(used),
            disabledReason: flowEditor.frames.any((f) => f.block == name)
                ? S.current.mbInsideItself
                : null,
            menu: [
              PaletteMenuItemVm('edit', S.current.mbEdit),
              PaletteMenuItemVm(
                'save',
                S.current.mbSave,
                disabledReason: config,
              ),
              PaletteMenuItemVm(
                'rename',
                S.current.mbRename,
                disabledReason: back,
              ),
              PaletteMenuItemVm(
                'update',
                S.current.mbUpdate,
                disabledReason: lib == null
                    ? S.current.mbNotInLibrary
                    : (lib.version == copied ? S.current.mbSameVersion : back),
              ),
              PaletteMenuItemVm(
                'delete',
                S.current.mbDelete,
                danger: true,
                disabledReason: used > 0 ? S.current.mbInUse(used) : back,
              ),
            ],
          );
        }(),
      for (final l in flowEditor.library)
        PaletteEntryVm(
          id: 'lib:${l.name}',
          title: l.name,
          tag: 'LIB',
          group: S.current.myBlocksLibrary,
          detail: l.description,
          value: S.current.mbVersion(l.version),
          disabledReason: flowEditor.frames.any((f) => f.block == l.name)
              ? S.current.mbInsideItself
              : null,
          menu: [
            PaletteMenuItemVm(
              'remove-library',
              S.current.mbRemoveLibrary,
              danger: true,
              disabledReason: config,
            ),
          ],
        ),
    ];
  }

  /// The children of [key] in the order the broker listed them.
  List<NodeInfo> _children(String key) => [
    for (final k in nodes.view)
      if (k.startsWith('$key/') && !k.substring(key.length + 1).contains('/'))
        ?nodes.table[k],
  ];

  /// The points of the open tree that may be written: dropped on the
  /// canvas they ask Read or Write.
  Set<String> _writable(String root) => {
    for (final n in nodes.table.values)
      if (n.type != null &&
          n.writable != null &&
          _treeSections.any((s) => n.key.startsWith('$root/$s/')))
        'key:${n.key}',
  };

  /// The Tree tab (spec §18): the site's tree as the Explorer draws it,
  /// extended for the editor. A node opens to its children; a value node
  /// is a leaf with its type tag and live value, dragged as a point; an
  /// open node lists its actions first, in ember, dragged as action
  /// blocks. With a filter: what holds it, and the nodes above, opened.
  List<TreeRowVm> _treeRows(String root, IMap<String, FlowBlock> blocks) {
    final out = <TreeRowVm>[];
    final q = flowEditor.treeQuery.trim().toLowerCase();
    final used = {
      for (final x in blocks.values)
        if (pointOf(x) case final k?) _full(root, k),
    };
    final keep = <String>{};
    void keepUp(String key) {
      final parts = key.split('/');
      for (var i = 3; i <= parts.length; i++) {
        keep.add(parts.sublist(0, i).join('/'));
      }
    }

    if (q.isNotEmpty) {
      for (final n in nodes.table.values) {
        if (n.name.toLowerCase().contains(q)) {
          keepUp(n.key);
        }
      }
      for (final MapEntry(:key, :value) in nodes.detail.entries) {
        if (value.actions.any((a) => a.name.toLowerCase().contains(q))) {
          keepUp(key);
        }
      }
    }
    void walk(
      String key,
      String name,
      int depth, {
      NodeInfo? info,
      bool section = false,
    }) {
      if (q.isNotEmpty && !keep.contains(key)) {
        return;
      }
      final typed = info?.type != null;
      final below = q.isNotEmpty && keep.any((k) => k.startsWith('$key/'));
      final open = nodes.expanded.contains(key) || below;
      final kids = open ? _children(key) : const <NodeInfo>[];
      // A flow may run what needs read or write: never a config action.
      final acts = [
        for (final a
            in nodes.detail[key]?.actions ?? const IListConst<ActionInfo>([]))
          if (a.level != 'config') a,
      ];
      final hits = q.isEmpty || name.toLowerCase().contains(q);
      // A node may hold values, which only its list tells; so it opens
      // until its list answered empty and it has no action.
      final opens =
          section ||
          (info?.hasChildren ?? false) ||
          (info?.isAction ?? false) ||
          (!typed &&
              !(nodes.listed.contains(key) && kids.isEmpty && acts.isEmpty));
      out.add(
        TreeRowVm(
          id: key,
          name: name,
          depth: depth,
          icon: AppIcon.nodeName(
            key: key,
            root: root,
            profile: info?.profile,
            type: info?.type,
          ),
          hasChildren: opens,
          expanded: open,
          marked: used.contains(key),
          tag: typed ? AppIcon.typeTag(info!.type) : null,
          drag: typed ? 'key:$key' : null,
          value: !typed
              ? null
              : switch (live.values[key]) {
                  null => null,
                  final v => valueText(
                    v.value,
                    choices:
                        nodes.detail[key]?.choices.unlock ??
                        info!.choices.unlock,
                    unit: info!.unit,
                  ),
                },
        ),
      );
      if (!open) {
        return;
      }
      for (final a in acts) {
        if (q.isEmpty || hits || a.name.toLowerCase().contains(q)) {
          out.add(
            TreeRowVm(
              id: '$key/~act/${a.name}',
              name: labelOf(a.name, display: a.display),
              depth: depth + 1,
              tag: 'ACT',
              ember: true,
              drag: 'act:$key/${a.name}',
              value: S.current.actionInputs(a.params.length),
            ),
          );
        }
      }
      for (final k in kids) {
        walk(k.key, k.name, depth + 1, info: k);
      }
    }

    for (final s in _treeSections) {
      walk('$root/$s', s, 0, section: true);
    }
    return out;
  }

  /// The Blocks tab: the engine's catalogue, one line per type.
  static List<PaletteEntryVm> _catalog(IList<NodeType> types) => [
    for (final t in inPaletteOrder(types))
      PaletteEntryVm(
        id: 'type:${t.type}',
        // In words; the engine's name is searched too (spec §2).
        title: blockLabel(t.type),
        tag: _sources.contains(t.type)
            ? 'IN'
            : (_sinks.contains(t.type) ? 'OUT' : 'FX'),
        group: t.category,
        detail: t.description.isEmpty ? t.type : '${t.type}: ${t.description}',
      ),
  ];

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
    required bool differs,
    int hops = 0,
  }) {
    final ed = flowEditor;
    final d = ed.draft;
    final inside = ed.frames.isNotEmpty;
    // Inside a custom block the nodes run under an instance: their rows
    // are `<instance>/<inner>`; opened from the palette they do not run.
    final eid = _engineId(b.id);
    final dep = inside ? null : ed.deployed?.blocks[b.id];
    final same = inside
        ? !differs
        : dep != null && dep.type == b.type && sameCfg(dep.cfg, b.cfg);
    final ports = eid == null
        ? null
        : (previewing ? ed.previewPorts : (same ? ed.ports : null));
    final point = _pointTypes.contains(b.type) ? pointOf(b) : null;
    final flow = ed.root?.id ?? '';
    final pub = previewing || !same || inside
        ? null
        : _published(root, flow, b);
    final tree = pub != null
        ? live.values[pub]
        : (point == null ? null : live.values[_full(root, point)]);
    final inPrefix = portKey('in', b.id, '');
    final outPrefix = portKey('out', b.id, '');
    final paramPrefix = portKey('param', b.id, '');
    final instance = d != null && isInstance(b.type);
    // The key of a value in the engine's rows: the block's own node, or,
    // for an instance of a custom block, the inner node its port stands
    // for (an input: the first inner input it feeds, as its echo too).
    String? engineKey(String k) {
      if (eid == null) {
        return null;
      }
      final (dir, port) = k.startsWith(inPrefix)
          ? ('in', k.substring(inPrefix.length))
          : k.startsWith(outPrefix)
          ? ('out', k.substring(outPrefix.length))
          : ('param', k.substring(paramPrefix.length));
      if (!instance) {
        return portKey(dir, eid, port);
      }
      final up = eid.substring(0, eid.length - b.id.length);
      final out = dir == 'out' ? instanceEnd(d, b, port, output: true) : null;
      final end = out ?? instanceEnd(d, b, port, output: false);
      return end == null
          ? null
          : portKey(out != null ? 'out' : 'in', '$up${end.$1}', end.$2);
    }

    LiveValue? look(String k) {
      final at = engineKey(k);
      final v = at == null ? null : ports?[at];
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
          // An instance's input holds its own constant, else the block's
          // default.
          final constant = f == null
              ? null
              : (instance
                    ? instanceValueOf(d, b, port)
                    : operandValueOf(b, port));
          return constant == null
              ? null
              : LiveValue(time: _typedTime, value: constant);
        }
        return _live(
          src,
          root,
          fields,
          previewing: previewing,
          differs: differs,
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
    final keyed = scopedKeyOf(t);
    final behaves = behavesOf(t);
    // The row a sink's ghost stands on: its value's, else its trigger's.
    final ghostRow = rows.any((f) => f.inPort == 'in')
        ? 'in:in'
        : (rows.any((f) => f.id == 'in:trigger')
              ? 'in:trigger'
              : rows.firstOrNull?.id);
    // What a sink would write in the preview (nothing is written).
    final ghost = previewing && _sinks.contains(b.type)
        ? flowEditor.previewSinks[_engineId(b.id) ?? b.id]
        : null;
    // The draft no longer runs: the preview's last values, greyed.
    final stale = previewing && flowEditor.previewError != null;
    final info = point == null ? null : nodes.table[_full(root, point)];
    final v = variadicOf(t, b);
    return FlowBlockVm(
      id: b.id,
      title: switch (b.id) {
        blockInputsId => S.current.blockInputs,
        blockOutputsId => S.current.blockOutputs,
        final x => x,
      },
      type: switch (role) {
        BlockRole.node => _connection(point, parent: true),
        // The action block names what it runs: `tcp-tank · ramp`.
        BlockRole.action => [
          _connection(point, parent: false).split('/').last,
          if (b.cfg['action'] case final String a when behaves) a,
        ].where((x) => x.isNotEmpty).join(' · '),
        BlockRole.custom => blockNameOf(b.type) ?? '',
        _ => b.type,
      },
      kind: switch (role) {
        BlockRole.node => BlockKindVm.node,
        BlockRole.logic => BlockKindVm.logic,
        BlockRole.sink => BlockKindVm.sink,
        BlockRole.action => BlockKindVm.action,
        BlockRole.custom => BlockKindVm.my,
      },
      link: isInstance(b.type) && flowEditor.caps.blocks
          ? S.current.openInside
          : null,
      x: b.x,
      y: b.y,
      // The inputs and outputs blocks of an inside view are narrow: names.
      width: isBoundary(b.id) ? 160 : blockWidthOf(role),
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
            final group = groupOf(t, b, f);
            final wouldDo = ghost != null && f.id == ghostRow
                ? (b.type == 'invoke'
                      ? (behaves
                            ? S.current.wouldSend(valueText(ghost.value))
                            : S.current.wouldRun(valueText(ghost.value)))
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
              // An event reads when it fired, not its map; a run its time.
              value:
                  wouldDo ??
                  switch (f.name) {
                    // A command is a button: it shows no value.
                    _ when f.command => '',
                    _ when group == FieldGroup.events =>
                      eventText(live(portKey('out', b.id, f.name))) ?? '',
                    'last_run' when behaves => lastRunText(value.raw) ?? '',
                    _ => value.text,
                  },
              // The scope is typed in its prompt: the pencil opens it.
              action: f.name == keyed?.scope ? 'action_edit' : null,
              actionTip: S.current.scopeEdit,
              command: f.command,
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
      variadic: isBoundary(b.id)
          ? VariadicVm(
              label: S.current.portsCount(rows.length),
              canRemove: rows.isNotEmpty,
              addLabel: S.current.addPort,
              removeLabel: S.current.removePort,
            )
          : v == null
          ? null
          // A pair of inputs (`case`) or a case with its output (`router`).
          : (v.step == 2 || v.outPrefix != null
                ? VariadicVm(
                    label: S.current.pairsCount(v.names.length ~/ v.step),
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
    BlockRole.custom => S.current.kindMyBlock,
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
    final t = flowEditor.allTypes.where((x) => x.type == b.type).firstOrNull;
    return valueViewerOf(
      title: '${b.id}.${f.name}',
      value: v.raw,
      known: v.raw != null || v.live,
      // A table's rows (ADR 0044 §2) and a date (µs, §3) by the field.
      rowsOfMaps: holdsTable(t, f.name),
      date: isTimeField(b.type, f.name),
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
    NodeType? t, {
    required String root,
    required ({String key, String scope, String port})? keyed,
    required String? runReason,
  }) {
    final behaves = behavesOf(t);
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
    // An unbound trigger is a button: the engine's `trigger` action on
    // the deployed flow (spec §19).
    if (f.id == 'in:trigger' && (t?.trigger ?? false)) {
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.run,
        value: S.current.runBlock,
        disabledReason: runReason,
        inPort: f.inPort,
      );
    }
    // A command (`date_range` Next, `table_page` First) is a button that a
    // sample on its wire presses; Studio has no way to press it itself.
    if (f.command) {
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.run,
        value: f.label,
        disabledReason: S.current.commandNote,
        inPort: f.inPort,
      );
    }
    if (b.id == blockInputsId) {
      // An input of a custom block: its default is typed here.
      final v = switch (b.cfg['defaults']) {
        final Map<Object?, Object?> m => m[f.name],
        _ => null,
      };
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        editor: FieldEditorVm.text,
        value: v == null ? '' : (v is String ? v : jsonEncode(v)),
        hint: S.current.cbDefault,
      );
    }
    final p = f.spec;
    if (p != null) {
      final v = b.cfg[p.name] ?? p.defaultValue;
      final scoped = p.name == keyed?.scope;
      final keyBound =
          keyed != null &&
          d.edges.any((e) => e.to == b.id && e.toPort == keyed.port);
      // A list of maps (`mapping`, `aggregates`): a line per item.
      final items = listItemsOf(t, p.name);
      // A time zone or a range text: a text with the usual ones in a menu.
      final suggested = isTimeZoneParam(b.type, p.name)
          ? timeZoneChoicesOf(b.type)
          : (isRangeText(b.type, p.name) ? rangeChoices : null);
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        rows: items == null
            ? null
            : RowsEditorVm(
                id: f.id,
                columns: [
                  for (final c in items)
                    RowsColumnVm(c.key, humanize(c.key), choices: c.choices),
                ],
                rows: listRowsOf(v),
                addLabel: S.current.rowsAdd,
                removeLabel: S.current.rowsRemove,
                emptyLabel: S.current.rowsEmpty,
              ),
        // A scope that the engine would refuse says why, once it matters.
        error: scoped && (keyBound || !_blank(v))
            ? _scopeError(root, v is String ? v : '') ?? ''
            : '',
        // `Run on start` asks first, with the catalog's own warning.
        confirm: p.name == 'run_on_start' && hint.startsWith('WARNING:')
            ? (S.current.runOnStartTitle, hint)
            : null,
        editor: items != null
            ? FieldEditorVm.rows
            : suggested != null
            ? FieldEditorVm.suggest
            : p.choices.isNotEmpty
            ? FieldEditorVm.choice
            : p.type == 'bool'
            ? FieldEditorVm.toggle
            : (p.name == 'interval_ms' && behaves
                  ? FieldEditorVm.duration
                  : FieldEditorVm.text),
        value: switch (v) {
          null => '',
          final Map<Object?, Object?> m => flowJson(m),
          final List<Object?> l => flowJson(l),
          _ => '$v',
        },
        choices: suggested ?? p.choices.unlock,
        inPort: f.inPort,
        hint: hint,
      );
    }
    if (f.kind == FieldKind.arg) {
      // An argument is typed as its action says: its choices, a toggle,
      // else a value.
      final v = (b.cfg['args'] as Map?)?[f.name];
      final spec = f.argSpec;
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: spec != null && spec.choices.isNotEmpty
            ? FieldEditorVm.choice
            : (spec?.type == 'bool'
                  ? FieldEditorVm.toggle
                  : FieldEditorVm.text),
        value: v == null ? '' : (v is String ? v : jsonEncode(v)),
        choices: spec?.choices.unlock ?? const [],
        inPort: f.inPort,
        hint: spec?.description ?? '',
      );
    }
    if (f.operand) {
      // An operand holds a typed constant until a binding replaces it;
      // an instance's input its own constant, else the block's default.
      final v = isInstance(b.type)
          ? instanceValueOf(d, b, f.inPort!)
          : operandValueOf(b, f.inPort!);
      // The range text of a `date_range`: a text with the usual ones.
      final range = isRangeText(b.type, f.name);
      return InspectorRowVm(
        id: f.id,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: range ? FieldEditorVm.suggest : FieldEditorVm.text,
        value: switch (v) {
          null => '',
          final String s => s,
          _ => jsonEncode(v),
        },
        choices: range ? rangeChoices : const [],
        inPort: f.inPort,
      );
    }
    final shown = fieldValue(b, f, d, live);
    final value = switch (f.name) {
      // An event: when it last fired, and for an error its code and
      // message; a run: its time.
      _ when groupOf(t, b, f) == FieldGroup.events =>
        eventText(live(portKey('out', b.id, f.name))) ?? S.current.eventNone,
      'last_run' when behaves => lastRunText(shown.raw) ?? S.current.eventNone,
      _ => shown.text,
    };
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
    required this.details,
    required this.run,
    required this.crumbs,
    required this.insideNote,
    required this.onBack,
    required this.myBlocksOff,
    required this.tree,
    required this.writable,
    required this.onTreeToggle,
    required this.onTreeQuery,
    required this.onPaletteMenu,
    required this.onRenameBlock,
    required this.validateBlockName,
    required this.createBlock,
    required this.validateBlock,
    required this.onCreateBlock,
    required this.prompt,
    required this.onPromptSave,
    required this.onPromptCancel,
    required this.validatePrompt,
    required this.onRowAction,
    required this.onOpen,
    required this.onRun,
    required this.openInside,
    required this.onOpenInside,
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
           details,
           crumbs,
           insideNote,
           myBlocksOff,
           tree,
           writable,
           prompt,
           openInside,
         ],
       );

  /// The nodes whose `~meta` the flow's action blocks wait for.
  final List<String> details;

  /// The custom blocks the canvas is inside of, outermost first.
  final List<String> crumbs;
  final String? insideNote;
  final ValueChanged<int> onBack;

  /// Why the My blocks tab is off; null: it is on.
  final String? myBlocksOff;

  /// The Tree tab's rows; null on the other tabs.
  final List<TreeRowVm>? tree;
  final Set<String> writable;
  final ValueChanged<String> onTreeToggle;
  final ValueChanged<String> onTreeQuery;
  final void Function(String entry, String item) onPaletteMenu;
  final void Function(String entry, String name) onRenameBlock;
  final String? Function(String name) validateBlockName;
  final CustomBlockDialogVm? Function() createBlock;
  final String? Function(CustomBlockResult result) validateBlock;
  final ValueChanged<CustomBlockResult> onCreateBlock;

  /// The scope asked of a key that got a wire.
  final ScopePromptVm? prompt;
  final ValueChanged<String> onPromptSave;
  final VoidCallback onPromptCancel;
  final String? Function(String scope) validatePrompt;
  final void Function(String block, String row) onRowAction;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRun;

  /// `Open inside` above the rows of a custom block's instance; null: the
  /// selected block is none.
  final String? openInside;
  final VoidCallback onOpenInside;

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
