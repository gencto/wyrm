import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/cancel_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/close_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/create_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_shown_flow_action.dart';
import 'package:business/redux/flow_editor/actions/edit_scope_action.dart';
import 'package:business/redux/flow_editor/actions/follow_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/leave_block_action.dart';
import 'package:business/redux/flow_editor/actions/new_flow_action.dart';
import 'package:business/redux/flow_editor/actions/open_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/open_instance_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_field_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/resize_block_action.dart';
import 'package:business/redux/flow_editor/actions/run_block_action.dart';
import 'package:business/redux/flow_editor/actions/save_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/select_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/set_tree_query_action.dart';
import 'package:business/redux/flow_editor/actions/set_viewed_field_action.dart';
import 'package:business/redux/flow_editor/actions/show_palette_tab_action.dart';
import 'package:business/redux/flow_editor/actions/toggle_tree_node_action.dart';
import 'package:business/redux/flow_editor/actions/unbind_field_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:ui/containers/side_panels.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/models/panels.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/shell/window_bar.dart';

import '../common/side_panels.dart';
import '../common/value_viewer.dart';
import '../common/window.dart';
import '../mappers/flow_editor_mappers.dart';
import '../mappers/flow_inspector_mappers.dart';
import '../mappers/flow_intent_mappers.dart';
import '../mappers/flow_queries.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class FlowEditorPageConnector extends StatelessWidget {
  const FlowEditorPageConnector({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    onInit: (store) => store.dispatch(OpenFlowEditorAction(id)),
    // What the editor follows (the Tree tab's points, the blocks' points,
    // the flow's `~val`, the preview and the engine's checks, the action
    // blocks' nodes): one step.
    onWillChange: (context, store, before, now) =>
        before.view.follow != now.view.follow
        ? store.dispatch(
            FollowFlowEditorAction(before.view.follow, now.view.follow),
          )
        : null,
    onDispose: (store) => store.dispatchSync(CloseFlowEditorAction(id)),
    builder: (context, vm) => FlowEditorPage(
      window: vm.window,
      flowName: vm.view.flowName,
      selected: vm.view.selected,
      selectedCount: vm.view.selectedCount,
      status: vm.view.status.vm,
      version: vm.view.version,
      stateDot: vm.view.dot,
      deployOff: vm.view.deployOff?.disabled,
      onDeploy: vm.onDeploy,
      onValidate: vm.onValidate,
      onClose: vm.onClose,
      onFlows: vm.onClose,
      myBlocksOff: vm.view.myBlocksOff,
      tree: vm.view.treeVms?.unlock,
      onTreeToggle: vm.onTreeToggle,
      onTreeQuery: vm.onTreeQuery,
      onPlace: vm.onPlace,
      onPaletteMenu: vm.onPaletteMenu,
      onRenameBlock: vm.onRenameBlock,
      onTreePlace: vm.onTreePlace,
      crumbs: vm.view.crumbs.unlock,
      onBack: vm.onBack,
      instances: vm.view.instances,
      createBlock: vm.view.customBlock?.vm,
      checkBlock: CustomBlockQuery(vm.view.questions),
      onCreateBlock: vm.onCreateBlock,
      checkBlockName: BlockNameQuery(vm.view.questions),
      prompt: vm.view.prompt?.vm,
      onPromptSave: vm.onPromptSave,
      onPromptCancel: vm.onPromptCancel,
      checkScope: ScopeQuery(vm.view.questions),
      onRun: vm.onRun,
      onForm: vm.onForm,
      onOpenInside: vm.onOpenInside,
      paletteTab: vm.view.palette.vm,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.view.paletteVms.unlock,
      blocks: [for (final x in vm.view.blocks) x.vm],
      wires: [for (final w in vm.view.wires) w.vm],
      onSelect: vm.onSelect,
      onBind: vm.onBind,
      onRebind: vm.onRebind,
      onUnbind: vm.onUnbind,
      onResize: vm.onResize,
      refusal: WireRefusalQuery(vm.view.questions),
      onOpen: vm.onOpen,
      onRowAction: vm.onRowAction,
      onClear: vm.onClear,
      onMove: vm.onMove,
      newFlowName: vm.newFlowName,
      inspector: vm.view.inspector?.head,
      inspectorRows: vm.view.inspector?.rowVms ?? const [],
      summary: vm.view.summary?.vm,
      onFieldChanged: vm.onFieldChanged,
      onFieldUnbind: vm.onFieldUnbind,
      onFieldBind: vm.onFieldBind,
      onProblem: vm.onSelect,
      onGoToSource: vm.onSelect,
      onRemove: vm.onRemove,
      onLogo: vm.onLogo,
      panels: vm.panelWidths,
      onPanelWidth: (side, width) => vm.onPanelWidth(PanelWidth(side, width)),
      viewer: vm.view.viewer?.vm,
      onView: vm.onView,
      onCloseViewer: vm.onCloseViewer,
      onSelectMany: vm.onSelectMany,
      onCommand: vm.onCommand,
      menu: FlowMenuQuery(vm.view.questions, onPin: vm.onPin),
      onViewField: vm.onViewField,
      onFieldPin: vm.onFieldPin,
      onSaveViewer: vm.onSaveViewer,
      checkViewer: ViewerTextQuery(vm.view.questions),
      viewerTables: viewerTables,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, FlowEditorPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final route = connector.id;
    final view = flowEditor.view(route);
    final sel = view.selected;
    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      view: view,
      panelWidths: WorkspacePanels.flowEditor.widths(panels.widths),
      onBack: (levels) => dispatchSync(LeaveBlockAction(levels: levels)),
      onTreeToggle: (key) => dispatch(ToggleTreeNodeAction(key)),
      onTreeQuery: (text) => dispatchSync(SetTreeQueryAction(text)),
      onPlace: (p) => _run(view.placing(p)),
      onPaletteMenu: (p) => _run(view.menuPick(p)),
      onRenameBlock: (r) => _run(view.renaming(r)),
      onTreePlace: (p) => _run(view.placingRow(p)),
      onCreateBlock: (r) =>
          dispatchSync(CreateCustomBlockAction.selected(r.spec)),
      onPromptSave: (scope) => dispatchSync(SaveScopePromptAction(scope)),
      onPromptCancel: () => dispatchSync(CancelScopePromptAction()),
      onRowAction: (r) => _run(view.onRow(r, EditScopeAction.new)),
      onOpen: (block) => dispatchSync(OpenInstanceAction(block)),
      onRun: (i) => _run(view.onField(i, (_, row) => RunBlockAction(row))),
      onForm: (f) => _run(view.form(f)),
      onOpenInside: switch (sel) {
        final at? when view.inspector?.openInside ?? false =>
          () => dispatchSync(OpenInstanceAction(at)),
        _ => null,
      },
      newFlowName: view.isNew
          ? FieldVm(
              value: view.flowName ?? '',
              onChanged: (v) => dispatchSync(NewFlowAction(v)),
            )
          : null,
      onView: (i) => _run(view.onField(i, SetViewedFieldAction.at)),
      onCloseViewer: () => dispatchSync(SetViewedFieldAction(null)),
      onDeploy: () => dispatch(DeployShownFlowAction()),
      onValidate: () => dispatch(ValidateFlowAction()),
      onClose: () => dispatch(GoAction.pop()),
      onPaletteTab: (t) => dispatch(ShowPaletteTabAction(t.tab)),
      onClear: () => dispatchSync(SetSelectedBlockAction(null)),
      onMove: (m) => dispatchSync(m.action),
      onSelect: (x) => dispatchSync(SetSelectedBlockAction(x)),
      onSelectMany: (s) =>
          dispatchSync(SelectBlocksAction(s.ids, add: s.add, toggle: s.toggle)),
      onCommand: (c) => _run(view.command(c)),
      onPin: (p) =>
          dispatchSync(SetFieldPinAction(p.block, p.field, pinned: p.on)),
      onFieldPin: (p) => _run(view.fieldPin(p)),
      onViewField: (r) => _run(view.onRow(r, SetViewedFieldAction.at)),
      onSaveViewer: (text) => _run(view.savedViewer(text)),
      onBind: (w) => dispatchSync(
        ConnectPortsAction(w.from.block, w.from.port, w.block, w.port),
      ),
      onUnbind: (r) => _run(view.onRow(r, UnbindFieldAction.new)),
      onRebind: (w) => dispatchSync(RebindFieldAction(w.from.end, w.to.end)),
      onResize: (r) => dispatchSync(ResizeBlockAction(r.block, add: r.add)),
      onFieldChanged: (t) => _run(view.fieldTyped(t)),
      onFieldUnbind: (i) => _run(view.onField(i, UnbindFieldAction.new)),
      onFieldBind: (b) => _run(view.fieldBound(b)),
      onRemove: sel == null
          ? null
          : () => dispatchSync(RemoveBlocksAction([sel])),
      onLogo: () => dispatch(GoAction.navigate(const ExplorerRoute())),
      onPanelWidth: (p) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.flowEditor.slot(p.side), p.width),
      ),
    );
  }

  /// Runs what a gesture does; null: it does nothing.
  void _run(Action? action) {
    if (action != null) {
      dispatchSync(action);
    }
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
///
/// Everything drawn is made of [view] (memoized: identical while nothing it
/// shows changed), [window] and [panelWidths], so those are what it compares:
/// the palette, the tree and the questions the widgets ask (each holding the
/// values its answers are made of) are made of [view] where they are drawn;
/// the callbacks only name what was done.
class _Vm extends Vm {
  _Vm({
    required this.window,
    required this.view,
    required this.panelWidths,
    required this.onBack,
    required this.onTreeToggle,
    required this.onTreeQuery,
    required this.onPlace,
    required this.onPaletteMenu,
    required this.onRenameBlock,
    required this.onTreePlace,
    required this.onCreateBlock,
    required this.onPromptSave,
    required this.onPromptCancel,
    required this.onRowAction,
    required this.onOpen,
    required this.onRun,
    required this.onForm,
    required this.onOpenInside,
    required this.newFlowName,
    required this.onDeploy,
    required this.onValidate,
    required this.onClose,
    required this.onPaletteTab,
    required this.onClear,
    required this.onMove,
    required this.onSelect,
    required this.onBind,
    required this.onUnbind,
    required this.onRebind,
    required this.onResize,
    required this.onFieldChanged,
    required this.onFieldUnbind,
    required this.onFieldBind,
    required this.onRemove,
    required this.onLogo,
    required this.onPanelWidth,
    required this.onView,
    required this.onCloseViewer,
    required this.onSelectMany,
    required this.onCommand,
    required this.onPin,
    required this.onFieldPin,
    required this.onViewField,
    required this.onSaveViewer,
  }) : super(
         equals: [
           window,
           view,
           panelWidths,
           // Made of [view], with a callback that only names what was done.
           newFlowName,
           onOpenInside != null,
           onRemove != null,
         ],
       );

  final WindowBarVm window;

  /// The business view of the editor: every value drawn is made of it.
  final FlowView view;
  final SidePanelWidths panelWidths;
  final ValueChanged<int> onBack;
  final ValueChanged<String> onTreeToggle;
  final ValueChanged<String> onTreeQuery;
  final ValueChanged<EntryPlaced> onPlace;
  final ValueChanged<EntryMenuPicked> onPaletteMenu;
  final ValueChanged<EntryRenamed> onRenameBlock;
  final ValueChanged<TreeRowPlaced> onTreePlace;
  final ValueChanged<CustomBlockResult> onCreateBlock;
  final ValueChanged<String> onPromptSave;
  final VoidCallback onPromptCancel;
  final ValueChanged<RowRef> onRowAction;
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onRun;
  final ValueChanged<BlockFormVm> onForm;
  final VoidCallback? onOpenInside;
  final FieldVm<String>? newFlowName;
  final VoidCallback onDeploy;
  final VoidCallback onValidate;
  final VoidCallback onClose;
  final ValueChanged<PaletteTabVm> onPaletteTab;
  final VoidCallback onClear;
  final ValueChanged<BlocksMoved> onMove;
  final ValueChanged<String> onSelect;
  final ValueChanged<BlocksSelected> onSelectMany;
  final ValueChanged<CanvasCommand> onCommand;
  final ValueChanged<PinPicked> onPin;
  final ValueChanged<RowPinned> onFieldPin;
  final ValueChanged<RowRef> onViewField;
  final ValueChanged<String> onSaveViewer;
  final ValueChanged<WireDropped> onBind;
  final ValueChanged<RowRef> onUnbind;
  final ValueChanged<WireMoved> onRebind;
  final ValueChanged<BlockResized> onResize;
  final ValueChanged<RowTyped> onFieldChanged;
  final ValueChanged<int> onFieldUnbind;
  final ValueChanged<RowBound> onFieldBind;
  final VoidCallback? onRemove;
  final VoidCallback onLogo;
  final ValueChanged<PanelWidth> onPanelWidth;
  final ValueChanged<int> onView;
  final VoidCallback onCloseViewer;
}
