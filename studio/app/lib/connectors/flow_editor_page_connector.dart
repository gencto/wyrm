import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
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
import 'package:business/redux/flow_editor/actions/palette_menu_action.dart';
import 'package:business/redux/flow_editor/actions/rebind_field_action.dart';
import 'package:business/redux/flow_editor/actions/remove_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/rename_custom_block_action.dart';
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
import 'package:business/redux/flow_editor/actions/type_field_action.dart';
import 'package:business/redux/flow_editor/actions/unbind_field_action.dart';
import 'package:business/redux/flow_editor/actions/validate_flow_action.dart';
import 'package:business/redux/panels/actions/set_panel_width_action.dart';
import 'package:business/wyrm/decode/block_cfg.dart';
import 'package:business/wyrm/decode/flow_val.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:business/wyrm/mappers/csv_table.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_canvas.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:business/wyrm/mappers/flow_mapper.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/block_type.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_block.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';
import 'package:models/flow_problem.dart';
import 'package:models/flow_problem_kind.dart';
import 'package:models/live_value.dart';
import 'package:models/node_type.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/port_end.dart';
import 'package:ui/containers/side_panels.dart';
import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/field_inspector.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/flow_status.dart';
import 'package:ui/flows/rows_editor.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/models/query.dart';
import 'package:ui/overlays/value_viewer.dart';
import 'package:ui/pages/flow_editor_page.dart';
import 'package:ui/shell/window_bar.dart';
import 'package:ui/tables/table_edits.dart';
import 'package:wyrm_client/wyrm_client.dart' show Status, TypeCode;

import '../common/side_panels.dart';
import '../common/value_viewer.dart';
import '../common/window.dart';
import '../mappers/flow_editor_mappers.dart';
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
      if (before.follow != now.follow) {
        store.dispatchSync(FollowFlowEditorAction(before.follow, now.follow));
      }
    },
    onDispose: (store) => store.dispatchSync(CloseFlowEditorAction(id)),
    builder: (context, vm) => FlowEditorPage(
      window: vm.window,
      flowName: vm.view.flowName,
      selected: vm.view.selected,
      selectedCount: vm.view.selectedCount,
      status: vm.status,
      version: vm.view.version,
      stateDot: vm.view.dot,
      deployOff: vm.deployOff,
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
      prompt: vm.prompt,
      onPromptSave: vm.onPromptSave,
      onPromptCancel: vm.onPromptCancel,
      checkScope: vm.checkScope,
      onRun: vm.onRun,
      onOpenInside: vm.onOpenInside,
      paletteTab: vm.paletteTab,
      onPaletteTab: vm.onPaletteTab,
      palette: vm.palette.unlock,
      blocks: vm.blocks.unlock,
      wires: vm.wires.unlock,
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
      nameField: vm.nameField,
      inspectorKind: vm.inspectorKind,
      inspectorTitle: vm.inspectorTitle,
      inspectorNote: vm.inspectorNote,
      inspectorRows: vm.inspectorRows.unlock,
      summary: vm.summary,
      onFieldChanged: vm.onFieldChanged,
      onFieldUnbind: vm.onFieldUnbind,
      onFieldBind: vm.onFieldBind,
      onProblem: vm.onProblem,
      onGoToSource: vm.onProblem,
      onRemove: vm.onRemove,
      onLogo: vm.onLogo,
      panels: vm.panelWidths,
      onPanelWidth: vm.onPanelWidth,
      viewer: vm.viewer,
      onView: vm.onView,
      onCloseViewer: vm.onCloseViewer,
      onSelectMany: vm.onSelectMany,
      onCommand: vm.onCommand,
      menu: vm.menu,
      onViewField: vm.onViewField,
      onFieldPin: vm.onFieldPin,
      onSaveViewer: vm.onSaveViewer,
      validateViewer: vm.validateViewer,
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
    final base = flowBaseOf(state, route);
    final root = base.root;
    final ed = flowEditor;
    // What the canvas shows: the flow, or the inside of a custom block.
    final d = base.draft;
    // The flow itself, with every inside view folded back into it.
    final flow = base.flow;
    final caps = base.caps;
    final types = base.types;
    final isNew = base.isNew;
    final id = base.id;
    final sel = ed.selectedBlock;
    final b = sel == null ? null : d?.blocks[sel];
    final differs = base.differs;
    final problems = ed.problems;
    final edges = d?.edges ?? const IListConst<FlowEdge>([]);
    final blocks = d?.blocks ?? const IMapConst<String, FlowBlock>({});
    final previewing = previewingOf(state, base);
    final fields = base.fields;
    final keyedSel = b == null ? null : scopedKeyOf(types[b.type]);
    // The field the viewer shows: its block and its field.
    final viewed = switch (ed.viewedField) {
      FieldAt(:final block, :final row) when blocks[block] != null => (
        blocks[block]!,
        fields[block]!.where((f) => f.id == row).firstOrNull,
      ),
      _ => null,
    };
    final live = flowLiveOf(state, base, previewing: previewing);
    LiveValue? Function(String) look(FlowBlock x) => live.of(x);
    String inLabelOf(String block, String port) =>
        fields[block]?.where((f) => f.inPort == port).firstOrNull?.label ??
        port;

    // The canvas reports a row by its place: the field there, as drawn.
    FieldId? rowAt(RowRef r) => view.rowAt(r.block, r.row);
    return _Vm(
      window: windowBar(fullScreen: window.fullScreen),
      follow: view.follow,
      view: view,
      onBack: (levels) => dispatchSync(LeaveBlockAction(levels: levels)),
      tree: switch (view.tree) {
        final rows? => [
          for (final e in rows) e.vm(view.root, (p) => _place(e.entry, p)),
        ].lock,
        null => null,
      },
      onTreeToggle: (key) => dispatchSync(ToggleTreeNodeAction(key)),
      onTreeQuery: (q) => dispatchSync(SetTreeQueryAction(q)),
      checkBlockName: QueryVm(
        (name) => SelectFlowEditor(
          currentState(),
        ).blockNameProblem(route, name)?.vm,
      ),
      createBlock: QueryVm(
        (_) => SelectFlowEditor(currentState()).customBlock(route)?.vm,
      ),
      checkBlock: QueryVm(
        (r) => SelectFlowEditor(
          currentState(),
        ).customBlockProblem(_specOf(r))?.vm,
      ),
      onCreateBlock: (r) =>
          dispatchSync(CreateCustomBlockAction.selected(_specOf(r))),
      prompt: view.prompt?.vm,
      onPromptSave: (scope) => dispatchSync(SaveScopePromptAction(scope)),
      onPromptCancel: () => dispatchSync(CancelScopePromptAction()),
      checkScope: QueryVm(
        (scope) => SelectFlowEditor(currentState()).scopeProblem(scope)?.vm,
      ),
      onRowAction: (r) {
        if (rowAt(r) case final row?) {
          dispatchSync(EditScopeAction(r.block, row));
        }
      },
      onOpen: (block) => dispatchSync(OpenInstanceAction(block)),
      onRun: (row) {
        if (RowId.fromKey(row) case final r?) {
          dispatchSync(RunBlockAction(r));
        }
      },
      onOpenInside: switch (sel) {
        final at? when view.inspector?.openInside ?? false =>
          () => dispatchSync(OpenInstanceAction(at)),
        _ => null,
      },
      status: view.status.vm,
      deployOff: view.deployOff?.disabled,
      paletteTab: view.palette.vm,
      palette: switch (view.palette) {
        PaletteTab.tree => const IListConst([]),
        PaletteTab.my => [
          for (final m in view.myBlocks)
            m.vm(
              place: (p) => _place(m.entry, p),
              onMenu: (item) =>
                  dispatchSync(PaletteMenuAction(m.name, item.item)),
              onRename: (name) =>
                  dispatchSync(RenameCustomBlockAction(m.name, name)),
            ),
          for (final l in view.library)
            l.vm(
              place: (p) => _place(l.entry, p),
              onMenu: (item) =>
                  dispatchSync(PaletteMenuAction(l.name, item.item)),
            ),
        ].lock,
        PaletteTab.blocks => [
          for (final c in view.catalog)
            c.vm((p) => _place(EnginePick(c.type), p)),
        ].lock,
      },
      blocks: [for (final x in view.blocks) x.vm].lock,
      wires: [for (final w in view.wires) w.vm].lock,
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
          ? const IListConst([])
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
            ].lock,
      summary: b == null
          ? _summary(root, id, flow, problems, previewing: previewing)
          : null,
      viewer: switch (ed.viewedField) {
        // The Form row: the form's name.
        FieldAt(block: final vb, row: FormRow()) when blocks[vb] != null =>
          switch (formOf(blocks[vb]!, edges)) {
            final form? => valueViewerOf(
              title: '$vb.${const FormRow().key}',
              value: form.label,
            ),
            null => null,
          },
        FieldAt(block: final vb, :final row)
            when d != null && blocks[vb] != null =>
          _viewer(
            blocks[vb]!,
            fields[vb]!.where((f) => f.id == row).firstOrNull,
            fields[vb]!,
            d,
            look(blocks[vb]!),
          ),
        _ => null,
      },
      onView: (row) {
        if ((sel, RowId.fromKey(row)) case (final at?, final id?)) {
          dispatchSync(SetViewedFieldAction(FieldAt(at, id)));
        }
      },
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
      menu: QueryVm(
        (ask) => SelectFlowEditor(currentState())
            .menu(
              route,
              MenuAsk(
                ask.ids.lock,
                block: ask.block,
                row: switch ((ask.block, ask.row)) {
                  (final b?, final r?) => view.rowAt(b, r),
                  _ => null,
                },
              ),
            )
            .vm(
              (field) => (on) {
                if (ask.block case final b?) {
                  dispatchSync(SetFieldPinAction(b, field, pinned: on));
                }
              },
            ),
      ),
      onFieldPin: (field, {required on}) {
        if ((sel, FieldId.fromKey(field)) case (final at?, final id?)) {
          dispatchSync(SetFieldPinAction(at, id, pinned: on));
        }
      },
      onViewField: (r) {
        if (rowAt(r) case final row?) {
          dispatchSync(SetViewedFieldAction(FieldAt(r.block, row)));
        }
      },
      onSaveViewer: (text) {
        if (ed.viewedField case FieldAt(:final block, :final row)) {
          dispatchSync(TypeFieldAction(block, row, text));
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
      onBind: (w) => dispatchSync(
        ConnectPortsAction(w.from.block, w.from.port, w.block, w.port),
      ),
      onUnbind: (r) {
        if (rowAt(r) case final row?) {
          dispatchSync(UnbindFieldAction(r.block, row));
        }
      },
      onRebind: (w) => dispatchSync(RebindFieldAction(w.from.end, w.to.end)),
      refusal: QueryVm(
        (ask) => switch (rowAt(ask.to)) {
          final row? =>
            SelectFlowEditor(currentState())
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
      onFieldChanged: (row, text) {
        if ((sel, RowId.fromKey(row)) case (final at?, final r?)) {
          dispatchSync(TypeFieldAction(at, r, text));
        }
      },
      onFieldUnbind: (row) {
        if ((sel, RowId.fromKey(row)) case (final at?, final r?)) {
          dispatchSync(UnbindFieldAction(at, r));
        }
      },
      onFieldBind: (row, from) {
        if ((sel, RowId.fromKey(row)) case (final at?, final r?)) {
          dispatchSync(BindFieldAction(at, r, PortEnd(from.block, from.port)));
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

  /// Places palette entry [entry] at [place] (a tap, a drop on the
  /// canvas or on an input); null: a row that only opens.
  void _place(PaletteEntry? entry, Place place) {
    if (entry != null) {
      if (placeActionOf(entry, place) case final action?) {
        dispatchSync(action);
      }
    }
  }

  /// What the dialog handed back as the block to make.
  static CustomBlockSpec _specOf(CustomBlockResult r) => customBlockSpecOf(
    name: r.name,
    description: r.description,
    inputs: r.inputs,
    outputs: r.outputs,
    defaults: r.defaults,
  );

  /// The id the engine knows block [id] of the canvas by: its own in the
  /// flow, `<instance>/<inner>` inside a custom block. Null inside a
  /// block opened from the palette: no instance, so no running node.
  String? _engineId(String id) => engineIdOf(flowEditor.frames, id);

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
    if (b.cfgEnabled == false) {
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

  /// `modbus/tcp-tank` of `downstream/modbus/tcp-tank/level` (the parent of a
  /// point, or a node itself), without `downstream`.
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
    List<FlowField> all,
    FlowDraft d,
    LiveValue? Function(String) live,
  ) {
    if (f == null) {
      return null;
    }
    final point = pointOf(b);
    final info = point == null
        ? null
        : nodes.table[fullKey(site.root ?? '', point)];
    final at = f.kind == FieldKind.input || f.kind == FieldKind.output;
    final v = fieldValue(b, f, d, live);
    final how = fieldEditOf(b, f, d.edges);
    final text = fieldEditText(b, f);
    final t = flowEditor.allTypes.where((x) => x.type == b.type).firstOrNull;
    final tabled = holdsTable(t, f.name);
    // A typed table (the `table` variable's Value, a table typed into a
    // table input) edits in the viewer's grid, from what the config holds;
    // an empty one starts with no columns (owner request 2026-11-11),
    // except the input of `table_from_json`, which takes a JSON text.
    final typedTable =
        tabled && (how.edit == FieldEdit.json || how.edit == FieldEdit.any)
        ? switch (fieldEditValue(b, f)) {
            null || '' when b.type.known != KnownBlock.tableFromJson =>
              TableDataVm.empty(),
            final x => tableDataOf(x, rowsOfMaps: true),
          }
        : null;
    final shownTable = v.raw == null && typedTable != null;
    return valueViewerOf(
      title: '${b.id}.${f.name}',
      value: shownTable ? typedTable.toJson() : v.raw,
      known: shownTable || v.raw != null || v.live,
      editable: typedTable != null,
      // A table's rows (ADR 0044 §2) and a date (µs, §3) by the field.
      rowsOfMaps: tabled,
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
        _ when typedTable != null => ViewerEditVm(
          kind: .table,
          text: text,
          table: typedTable,
        ),
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
      csv: b.type.known == KnownBlock.tableFromCsv && f.name == 'in'
          ? _csvRules(b, all, d, live)
          : null,
    );
  }

  /// How `table_from_csv` [b] reads its text: its `delimiter` and
  /// `with_header` as typed (their defaults `,` and true), or as a wire
  /// brings them now, with a note that says so.
  ViewerCsvVm _csvRules(
    FlowBlock b,
    List<FlowField> all,
    FlowDraft d,
    LiveValue? Function(String) live,
  ) {
    var wired = false;
    Object? read(String name) {
      final f = all.where((x) => x.spec?.name == name).firstOrNull;
      if (f == null) {
        return b.cfg[name];
      }
      final shown = fieldValue(b, f, d, live);
      wired = wired || shown.bound;
      return shown.raw ?? (b.cfg[name] ?? f.spec?.defaultValue);
    }

    final delimiter = read('delimiter');
    final header = read('with_header');
    return ViewerCsvVm(
      delimiter: csvDelimiter(delimiter),
      header: header is! bool || header,
      note: wired ? S.current.viewerCsvWired : '',
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
    required ScopedKey? keyed,
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
        id: f.id.key,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: FieldEditorVm.bound,
        value: fieldValue(b, f, d, live).text,
        sourceBlock: into.from,
        writes: writesTo(b.type),
        inPort: f.inPort,
        hint: hint,
      );
    }
    // An unbound trigger is a button: the engine's `trigger` action on
    // the deployed flow (spec §19).
    if (f.id == FieldId.input(EnginePort.trigger.wire) &&
        (t?.trigger ?? false)) {
      return InspectorRowVm(
        id: f.id.key,
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
        id: f.id.key,
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
      final v = b.cfgDefaults[f.name];
      return InspectorRowVm(
        id: f.id.key,
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
        id: f.id.key,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        rows: items == null
            ? null
            : RowsEditorVm(
                id: f.id.key,
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
        error: scoped && (keyBound || (v is String && v.trim().isNotEmpty))
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
            : p.type == TypeCode.bool_
            ? FieldEditorVm.toggle
            // `now`'s clock is a period as a command's (spec 06 0.2.30)
            : (p.name == 'interval_ms' &&
                      (behaves || b.type.known == KnownBlock.now)
                  ? FieldEditorVm.duration
                  : FieldEditorVm.text),
        value: switch (v) {
          Map() || List() => jsonEditText(v),
          null => '',
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
      final v = b.cfgArgs[f.name];
      final spec = f.argSpec;
      return InspectorRowVm(
        id: f.id.key,
        name: f.label,
        engine: f.name == f.label ? '' : f.name,
        editor: spec != null && spec.choices.isNotEmpty
            ? FieldEditorVm.choice
            : (spec?.type == TypeCode.bool_
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
        id: f.id.key,
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
        eventText(live(portKey(PortSide.output, b.id, f.name))) ??
            S.current.eventNone,
      'last_run' when behaves => lastRunText(shown.raw) ?? S.current.eventNone,
      _ => shown.text,
    };
    if (f.kind == FieldKind.output) {
      return InspectorRowVm(
        id: f.id.key,
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
      id: f.id.key,
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
    IList<FlowProblem> problems, {
    required bool previewing,
  }) {
    final own = live.values['$root/dataflows/$id'];
    final val = flowValOf(own?.value).orWarn('flow $id');
    final known = flows.table[id];
    final by = val?.deployedBy ?? known?.deployedBy;
    final maxperm = d?.permissions?.maxperm?.wireName;
    final keys = d == null ? null : flowKeysOf(d);
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
        if (flowEditor.watchRefused == Status.permissionDenied ||
            flowEditor.previewOff == Status.permissionDenied)
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
          ProblemVm(
            S.current.previewInvalid(_problemText(m)),
            block: m.block,
          ),
        for (final p in problems) ProblemVm(_problemText(p), block: p.block),
      ],
    );
  }

  /// A problem as the editor has always said it (phase B2 moves the
  /// words to `ui`).
  static String _problemText(FlowProblem p) => switch (p.kind) {
    FlowProblemKind.unnamed => 'name the flow',
    FlowProblemKind.broker => p.message ?? 'invalid',
    FlowProblemKind.unread => 'invalid',
  };

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
    required this.follow,
    required this.view,
    required this.onBack,
    required this.tree,
    required this.onTreeToggle,
    required this.onTreeQuery,
    required this.checkBlockName,
    required this.createBlock,
    required this.checkBlock,
    required this.onCreateBlock,
    required this.prompt,
    required this.onPromptSave,
    required this.onPromptCancel,
    required this.checkScope,
    required this.onRowAction,
    required this.onOpen,
    required this.onRun,
    required this.onOpenInside,
    required this.status,
    required this.deployOff,
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
    required this.onFieldPin,
    required this.onViewField,
    required this.onSaveViewer,
    required this.validateViewer,
  }) : super(
         equals: [
           window,
           follow,
           // The business view: memoized, so equal (identical) when
           // nothing it shows changed; then what is made of it.
           view,
           status,
           deployOff,
           paletteTab,
           palette,
           tree,
           prompt,
           onOpenInside != null,
           // Answered when asked, from the state then: equal by design.
           checkBlockName,
           createBlock,
           checkBlock,
           checkScope,
           menu,
           refusal,
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

  /// The business view: the path, the status, the palette's parts (what
  /// the top bar and the palette draw, compared by [equals]).
  final FlowView view;
  final ValueChanged<int> onBack;

  /// The Tree tab's rows; null on the other tabs.
  final IList<PaletteTreeRowVm>? tree;
  final ValueChanged<String> onTreeToggle;
  final ValueChanged<String> onTreeQuery;

  /// Questions the dialogs and the menu ask when the user acts: answered
  /// from the state then, so they are not compared.
  final QueryVm<String, CustomBlockProblemVm?> checkBlockName;
  final QueryVm<void, CustomBlockDialogVm?> createBlock;
  final QueryVm<CustomBlockResult, CustomBlockProblemVm?> checkBlock;
  final ValueChanged<CustomBlockResult> onCreateBlock;

  /// The scope asked of a key that got a wire.
  final ScopePromptVm? prompt;
  final ValueChanged<String> onPromptSave;
  final VoidCallback onPromptCancel;
  final QueryVm<String, ScopeProblemVm?> checkScope;
  final ValueChanged<RowRef> onRowAction;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRun;

  /// `Open inside` above the rows of a custom block's instance; null: the
  /// selected block is none.
  final VoidCallback? onOpenInside;

  /// The frameless window's side of the top bar.
  final WindowBarVm window;

  /// What the editor follows: the keys it watches, the draft it runs as a
  /// preview, the nodes whose `~meta` its action blocks wait for.
  final FlowFollow follow;
  final FlowStatusVm status;
  final Disabled? deployOff;
  final PaletteTabVm paletteTab;
  final IList<PaletteEntryVm> palette;
  final IList<FlowBlockVm> blocks;
  final IList<FlowWireVm> wires;
  final ParamFieldVm? nameField;
  final String inspectorKind;
  final String inspectorTitle;
  final String inspectorNote;
  final IList<InspectorRowVm> inspectorRows;
  final FlowSummaryVm? summary;
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
  final void Function(String field, {required bool on}) onFieldPin;
  final ValueChanged<RowRef> onViewField;
  final ValueChanged<String> onSaveViewer;
  final String? Function(String text) validateViewer;
  final ValueChanged<WireDropped> onBind;
  final ValueChanged<RowRef> onUnbind;
  final ValueChanged<WireMoved> onRebind;

  /// Why a row does not take a dragged wire: answered from the state then.
  final QueryVm<BindAsk, BindRefusalVm?> refusal;
  final ValueChanged<BlockResized> onResize;
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
