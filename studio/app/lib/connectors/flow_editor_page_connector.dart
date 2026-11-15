import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/bind_field_action.dart';
import 'package:business/redux/flow_editor/actions/cancel_scope_prompt_action.dart';
import 'package:business/redux/flow_editor/actions/close_flow_editor_action.dart';
import 'package:business/redux/flow_editor/actions/connect_ports_action.dart';
import 'package:business/redux/flow_editor/actions/create_custom_block_action.dart';
import 'package:business/redux/flow_editor/actions/deploy_flow_action.dart';
import 'package:business/redux/flow_editor/actions/edit_scope_action.dart';
import 'package:business/redux/flow_editor/actions/flow_edit_action.dart';
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
import 'package:business/redux/flow_editor/actions/set_block_form_action.dart';
import 'package:business/redux/flow_editor/actions/set_field_pin_action.dart';
import 'package:business/redux/flow_editor/actions/set_selected_block_action.dart';
import 'package:business/redux/flow_editor/actions/set_tree_query_action.dart';
import 'package:business/redux/flow_editor/actions/set_viewed_field_action.dart';
import 'package:business/redux/flow_editor/actions/show_palette_tab_action.dart';
import 'package:business/redux/flow_editor/actions/toggle_tree_node_action.dart';
import 'package:business/redux/flow_editor/actions/type_field_action.dart';
import 'package:business/redux/flow_editor/actions/unbind_field_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:material_ui/material_ui.dart' hide Action;
import 'package:models/field_id.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/models/panels.dart';
import 'package:ui/models/query.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/shell/window_bar.dart';

import '../common/side_panels.dart';
import '../common/value_viewer.dart';
import '../common/window.dart';
import '../mappers/flow_editor_mappers.dart';
import '../mappers/flow_inspector_mappers.dart';
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
    // the flow's `~val`, the preview, the action blocks' nodes): one step.
    onWillChange: (context, store, before, now) {
      if (before.view.follow != now.view.follow) {
        store.dispatchSync(
          FollowFlowEditorAction(before.view.follow, now.view.follow),
        );
      }
    },
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
      tree: vm.tree?.unlock,
      onTreeToggle: vm.onTreeToggle,
      onTreeQuery: vm.onTreeQuery,
      crumbs: vm.view.crumbs.unlock,
      onBack: vm.onBack,
      instances: vm.view.instances,
      createBlock: vm.createBlock,
      checkBlock: vm.checkBlock,
      onCreateBlock: vm.onCreateBlock,
      checkBlockName: vm.checkBlockName,
      prompt: vm.view.prompt?.vm,
      onPromptSave: vm.onPromptSave,
      onPromptCancel: vm.onPromptCancel,
      checkScope: vm.checkScope,
      onRun: vm.onRun,
      onForm: vm.onForm,
      onOpenInside: vm.onOpenInside,
      paletteTab: vm.view.palette.vm,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.palette.unlock,
      blocks: [for (final x in vm.view.blocks) x.vm],
      wires: [for (final w in vm.view.wires) w.vm],
      onSelect: vm.onSelect,
      onBind: vm.onBind,
      onRebind: vm.onRebind,
      onUnbind: vm.onUnbind,
      onResize: vm.onResize,
      refusal: vm.refusal,
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
      menu: vm.menu,
      onViewField: vm.onViewField,
      onFieldPin: vm.onFieldPin,
      onSaveViewer: vm.onSaveViewer,
      checkViewer: vm.checkViewer,
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
    // The canvas reports a row by its place, the inspector by its index:
    // the field there, as drawn.
    FieldId? rowAt(RowRef r) => view.rowAt(r.block, r.row);
    RowId? fieldAt(int row) => view.inspector?.rowAt(row);
    ValueChanged<RowRef> onRow(Action Function(String, FieldId) act) => (r) {
      if (rowAt(r) case final row?) {
        dispatchSync(act(r.block, row));
      }
    };
    ValueChanged<int> onField(Action Function(String, RowId) act) => (i) {
      if ((sel, fieldAt(i)) case (final at?, final row?)) {
        dispatchSync(act(at, row));
      }
    };
    SelectFlowEditor now() => SelectFlowEditor(currentState());
    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      view: view,
      panelWidths: WorkspacePanels.flowEditor.widths(panels.widths),
      onBack: (levels) => dispatchSync(LeaveBlockAction(levels: levels)),
      tree: view.treeVms(dispatchSync),
      onTreeToggle: (key) => dispatchSync(ToggleTreeNodeAction(key)),
      onTreeQuery: (q) => dispatchSync(SetTreeQueryAction(q)),
      checkBlockName: QueryVm(
        (name) => now().blockNameProblem(route, name)?.vm,
      ),
      createBlock: QueryVm((_) => now().customBlock(route)?.vm),
      checkBlock: QueryVm((r) => now().customBlockProblem(r.spec)?.vm),
      onCreateBlock: (r) =>
          dispatchSync(CreateCustomBlockAction.selected(r.spec)),
      onPromptSave: (scope) => dispatchSync(SaveScopePromptAction(scope)),
      onPromptCancel: () => dispatchSync(CancelScopePromptAction()),
      checkScope: QueryVm((scope) => now().scopeProblem(scope)?.vm),
      onRowAction: onRow(EditScopeAction.new),
      onOpen: (block) => dispatchSync(OpenInstanceAction(block)),
      onRun: onField((_, row) => RunBlockAction(row)),
      onForm: (f) {
        if (sel != null) {
          dispatchSync(SetBlockFormAction(sel, f.id));
        }
      },
      onOpenInside: switch (sel) {
        final at? when view.inspector?.openInside ?? false =>
          () => dispatchSync(OpenInstanceAction(at)),
        _ => null,
      },
      palette: view.paletteVms(dispatchSync),
      newFlowName: view.isNew
          ? FieldVm(
              value: view.flowName ?? '',
              onChanged: (v) => dispatchSync(NewFlowAction(v)),
            )
          : null,
      onView: onField((at, row) => SetViewedFieldAction(FieldAt(at, row))),
      onCloseViewer: () => dispatchSync(SetViewedFieldAction(null)),
      onDeploy: () => dispatch(DeployFlowAction()),
      onValidate: () => dispatch(ValidateFlowAction()),
      onClose: () => dispatch(GoAction.pop()),
      onPaletteTab: (t) => dispatchSync(ShowPaletteTabAction(t.tab)),
      onClear: () => dispatchSync(SetSelectedBlockAction(null)),
      onMove: (m) => dispatchSync(m.action),
      onSelect: (x) => dispatchSync(SetSelectedBlockAction(x)),
      onSelectMany: (s) =>
          dispatchSync(SelectBlocksAction(s.ids, add: s.add, toggle: s.toggle)),
      onCommand: (c) {
        if (c.command.edit case final e?) {
          dispatchSync(FlowEditAction(e, x: c.at?.dx, y: c.at?.dy));
        }
      },
      menu: QueryVm((ask) {
        final block = ask.block;
        final row = ask.row;
        return now()
            .menu(
              route,
              MenuAsk(
                ask.ids.lock,
                block: block,
                row: block == null || row == null
                    ? null
                    : rowAt(RowRef(block, row)),
              ),
            )
            .vm(
              (field) => (on) {
                if (block != null) {
                  dispatchSync(SetFieldPinAction(block, field, pinned: on));
                }
              },
            );
      }),
      onFieldPin: (p) {
        if ((sel, fieldAt(p.row)) case (final at?, final FieldId id)) {
          dispatchSync(SetFieldPinAction(at, id, pinned: p.on));
        }
      },
      onViewField: onRow((b, row) => SetViewedFieldAction(FieldAt(b, row))),
      onSaveViewer: (text) {
        if (flowEditor.viewedField case FieldAt(:final block, :final row)) {
          dispatchSync(TypeFieldAction(block, row, text));
        }
      },
      checkViewer: QueryVm((text) => now().viewerTextError(route, text)?.vm),
      onBind: (w) => dispatchSync(
        ConnectPortsAction(w.from.block, w.from.port, w.block, w.port),
      ),
      onUnbind: onRow(UnbindFieldAction.new),
      onRebind: (w) => dispatchSync(RebindFieldAction(w.from.end, w.to.end)),
      refusal: QueryVm(
        (ask) => switch (rowAt(ask.to)) {
          final row? =>
            now()
                .refusal(
                  route,
                  WireAsk(
                    ask.from.end,
                    ask.to.block,
                    row,
                    replacing: ask.replacing?.end,
                  ),
                )
                ?.vm,
          null => null,
        },
      ),
      onResize: (r) => dispatchSync(ResizeBlockAction(r.block, add: r.add)),
      onFieldChanged: (t) {
        if ((sel, fieldAt(t.row)) case (final at?, final row?)) {
          dispatchSync(TypeFieldAction(at, row, t.text));
        }
      },
      onFieldUnbind: onField(UnbindFieldAction.new),
      onFieldBind: (b) {
        if ((sel, fieldAt(b.row)) case (final at?, final row?)) {
          dispatchSync(BindFieldAction(at, row, b.from.end));
        }
      },
      onRemove: sel == null
          ? null
          : () => dispatchSync(RemoveBlocksAction([sel])),
      onLogo: () => dispatch(GoAction.navigate(const ExplorerRoute())),
      onPanelWidth: (p) => dispatchSync(
        SetPanelWidthAction(WorkspacePanels.flowEditor.slot(p.side), p.width),
      ),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
///
/// Everything drawn is made of [view] (memoized: identical while nothing it
/// shows changed), [window] and [panelWidths], so those are what it compares;
/// the callbacks only name what was done, and the questions are answered
/// from the state when they are asked.
class _Vm extends Vm {
  _Vm({
    required this.window,
    required this.view,
    required this.panelWidths,
    required this.onBack,
    required this.tree,
    required this.onTreeToggle,
    required this.onTreeQuery,
    required this.checkBlockName,
    required this.createBlock,
    required this.checkBlock,
    required this.onCreateBlock,
    required this.onPromptSave,
    required this.onPromptCancel,
    required this.checkScope,
    required this.onRowAction,
    required this.onOpen,
    required this.onRun,
    required this.onForm,
    required this.onOpenInside,
    required this.palette,
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
    required this.refusal,
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
    required this.menu,
    required this.onFieldPin,
    required this.onViewField,
    required this.onSaveViewer,
    required this.checkViewer,
  }) : super(
         equals: [
           window,
           view,
           panelWidths,
           // Made of [view], with callbacks that only name what was done.
           tree,
           palette,
           newFlowName,
           // Answered when asked, from the state then: equal by design.
           checkBlockName,
           createBlock,
           checkBlock,
           checkScope,
           refusal,
           menu,
           checkViewer,
         ],
       );

  final WindowBarVm window;

  /// The business view of the editor: every value drawn is made of it.
  final FlowView view;
  final SidePanelWidths panelWidths;
  final ValueChanged<int> onBack;
  final IList<PaletteTreeRowVm>? tree;
  final ValueChanged<String> onTreeToggle;
  final ValueChanged<String> onTreeQuery;
  final QueryVm<String, CustomBlockProblemVm?> checkBlockName;
  final QueryVm<void, CustomBlockDialogVm?> createBlock;
  final QueryVm<CustomBlockResult, CustomBlockProblemVm?> checkBlock;
  final ValueChanged<CustomBlockResult> onCreateBlock;
  final ValueChanged<String> onPromptSave;
  final VoidCallback onPromptCancel;
  final QueryVm<String, ScopeProblemVm?> checkScope;
  final ValueChanged<RowRef> onRowAction;
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onRun;
  final ValueChanged<BlockFormVm> onForm;
  final VoidCallback? onOpenInside;
  final IList<PaletteEntryVm> palette;
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
  final QueryVm<FlowMenuAsk, FlowMenuVm> menu;
  final ValueChanged<RowPinned> onFieldPin;
  final ValueChanged<RowRef> onViewField;
  final ValueChanged<String> onSaveViewer;
  final QueryVm<String, ViewerTextProblemVm?> checkViewer;
  final ValueChanged<WireDropped> onBind;
  final ValueChanged<RowRef> onUnbind;
  final ValueChanged<WireMoved> onRebind;
  final QueryVm<BindAsk, BindRefusalVm?> refusal;
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
