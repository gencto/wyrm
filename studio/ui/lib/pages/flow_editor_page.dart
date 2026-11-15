import 'dart:async';

import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/fault_boundary.dart';
import '../containers/side_panels.dart';
import '../flows/block_palette.dart';
import '../flows/custom_block_dialog.dart';
import '../flows/field_inspector.dart';
import '../flows/flow_block_view.dart';
import '../flows/flow_canvas.dart';
import '../flows/flow_menu.dart';
import '../flows/flow_status.dart';
import '../flows/scope_prompt.dart';
import '../flows/shortcut_card.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../models/disabled.dart';
import '../models/panels.dart';
import '../models/query.dart';
import '../models/value_changed.dart';
import '../overlays/confirm_dialog.dart';
import '../overlays/value_viewer.dart';
import '../shell/window_bar.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// Boards *Flow editor · fields, bindings, properties* and *· drag points
/// and actions from the tree* (studio/docs/design/specs/flow-editor.md): the
/// top bar (path, draft state, Validate, Deploy), the palette (Blocks, My
/// blocks, Tree), the canvas of fields and wires, and the inspector of the
/// selected block or of the flow.
class FlowEditorPage extends StatelessWidget {
  const FlowEditorPage({
    required this.status,
    required this.onValidate,
    required this.onClose,
    required this.onFlows,
    required this.onLogo,
    required this.paletteTab,
    required this.onPaletteTab,
    required this.palette,
    required this.blocks,
    required this.wires,
    required this.blockActions,
    required this.onClear,
    required this.onMove,
    required this.onFieldChanged,
    required this.onFieldUnbind,
    required this.onFieldBind,
    required this.onProblem,
    this.flowName,
    this.version = 0,
    this.selected,
    this.selectedCount = 0,
    this.stateDot = false,
    this.onDeploy,
    this.deployOff,
    this.myBlocksOff = false,
    this.paletteClosed = const {},
    this.nameField,
    this.inspectorKind = '',
    this.inspectorTitle = '',
    this.inspectorNote = '',
    this.inspectorRows = const [],
    this.summary,
    this.onRemove,
    this.panels = const SidePanelWidths(),
    this.onPanelWidth,
    this.onGoToSource,
    this.viewer,
    this.onView,
    this.onCloseViewer,
    this.window = const WindowBarVm(),
    this.onSelectMany,
    this.onCommand,
    this.menu,
    this.onPin,
    this.onViewField,
    this.onFieldPin,
    this.onSaveViewer,
    this.validateViewer,
    this.viewerTables,
    this.mac,
    this.crumbs = const [],
    this.onBack,
    this.instances,
    this.tree,
    this.onTreeToggle,
    this.onTreeQuery,
    this.createBlock,
    this.checkBlock,
    this.onCreateBlock,
    this.checkBlockName,
    this.prompt,
    this.onPromptSave,
    this.onPromptCancel,
    this.checkScope,
    this.onRun,
    this.onOpenInside,
    super.key,
  });

  /// The custom blocks the canvas is inside of, outermost first (spec
  /// §20): the path reads `Flows › <flow> › <block> …`, each part a link
  /// back to its level; empty: the canvas shows the flow.
  final List<String> crumbs;

  /// Back by so many levels (`Back`: one; the flow's name: all).
  final ValueChanged<int>? onBack;

  /// Inside a block: how many instances of it the flow has (said beside
  /// the path: `2 instances in this flow`); null: the flow itself.
  final int? instances;

  /// The Tree tab's rows (spec §18); null on the other tabs.
  final List<PaletteTreeRowVm>? tree;
  final ValueChanged<String>? onTreeToggle;
  final ValueChanged<String>? onTreeQuery;

  /// What `Create custom block…` asks of the selection; null: nothing to
  /// make a block of.
  final QueryVm<void, CustomBlockDialogVm?>? createBlock;

  /// Why the block the dialog would create is refused; null: it is taken.
  final QueryVm<CustomBlockResult, CustomBlockProblemVm?>? checkBlock;
  final ValueChanged<CustomBlockResult>? onCreateBlock;

  /// Why a new name of a custom block (Rename) is refused.
  final QueryVm<String, CustomBlockProblemVm?>? checkBlockName;

  /// The scope asked of a key that got a wire (spec §17).
  final ScopePromptVm? prompt;
  final ValueChanged<String>? onPromptSave;
  final VoidCallback? onPromptCancel;
  final QueryVm<String, ScopeProblemVm?>? checkScope;

  /// The `Run` button of an inspector row (an unbound `Trigger`).
  final ValueChanged<String>? onRun;

  /// `Open inside` above the inspector's rows (an instance of a custom
  /// block); null: none.
  final VoidCallback? onOpenInside;

  /// A marquee or Select all on the canvas.
  final void Function(
    Set<String> ids, {
    required bool add,
    required bool toggle,
  })?
  onSelectMany;

  /// A command of the canvas (copy, paste at `at`, delete, undo, …). The
  /// page itself answers two: `searchPalette` puts the cursor in the
  /// palette's search field, `deploy` asks first and then calls
  /// [onDeploy].
  final void Function(FlowCommand command, {Offset? at})? onCommand;

  /// The context menu of a block, of the selection or of the canvas.
  final QueryVm<FlowMenuAsk, FlowMenuVm>? menu;

  /// A field pinned to its block or taken off it, from the context menu.
  final void Function(String block, String field, {required bool pinned})?
  onPin;

  /// `V` over a row of the canvas: opens its value in the viewer.
  final RowAction<String, String>? onViewField;

  /// The pin of an inspector row (a field of the selected block).
  final Toggled<String>? onFieldPin;

  /// Save of the viewer's Edit mode: the editor's text.
  final ValueChanged<String>? onSaveViewer;

  /// What is wrong with a text typed in the viewer; null: it saves.
  final Validate<String>? validateViewer;

  /// How the viewer reads and writes tables (a date cell, CSV).
  final ViewerTables? viewerTables;

  /// ⌘ (true) or Ctrl in the viewer's save hint; null: this machine's.
  final bool? mac;

  /// The flow's id; null: a new flow not named yet (`New dataflow`).
  final String? flowName;

  /// The selected block, if one is.
  final String? selected;

  /// How many blocks are selected (several: `3 blocks` in the path).
  final int selectedCount;

  /// Where the draft stands (`Draft saved`, `Version 4 · deployed`), with
  /// the deployed [version].
  final FlowStatusVm status;
  final int version;

  /// A teal dot before the status (a draft that differs from the deployed
  /// one).
  final bool stateDot;
  final VoidCallback onValidate;
  final VoidCallback onClose;
  final VoidCallback onFlows;
  final VoidCallback? onDeploy;

  /// Why Deploy is off (`Nothing to deploy`); null: it is on.
  final Disabled? deployOff;

  final PaletteTabVm paletteTab;
  final ValueChanged<PaletteTabVm> onPaletteTab;

  /// The broker has no custom blocks: the My blocks tab is off.
  final bool myBlocksOff;
  final List<PaletteEntryVm> palette;

  /// Palette groups shown closed at first.
  final Set<String> paletteClosed;

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final FlowBlockActions blockActions;
  final VoidCallback onClear;
  final void Function(Map<String, Offset> to, {required bool nudge}) onMove;

  /// The id field of a new flow.
  final ParamFieldVm? nameField;
  final String inspectorKind;
  final String inspectorTitle;
  final String inspectorNote;
  final List<InspectorRowVm> inspectorRows;
  final FlowSummaryVm? summary;
  final FieldEdited onFieldChanged;
  final ValueChanged<String> onFieldUnbind;
  final FieldBound<FieldRefVm> onFieldBind;
  final ValueChanged<String> onProblem;
  final VoidCallback? onRemove;

  /// `Go to source` of a bound field in the inspector: selects the block.
  final ValueChanged<String>? onGoToSource;

  /// The open value viewer of a field, live; null: none is open.
  final ValueViewerVm? viewer;

  /// The eye of an inspector row (its id): opens the viewer.
  final ValueChanged<String>? onView;
  final VoidCallback? onCloseViewer;

  /// The frameless window's side of the top bar (docs/studio.md §7.1).
  final WindowBarVm window;

  /// The flow's name in the path: its id, or `New dataflow`.
  String get _flowLabel => flowName ?? S.current.newDataflow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final deployOn = deployOff == null && onDeploy != null;
    final flowLabel = _flowLabel;
    final blockLabel =
        selected ??
        (selectedCount > 1 ? S.current.fmBlocks(selectedCount) : null);
    return Scaffold(
      backgroundColor: c.ground0,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: AppSizes.flowTopBar),
              padding: Insets.flowTopBar,
              decoration: BoxDecoration(
                color: c.ground0,
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: WindowBar(
                vm: window,
                padding: AppSpacing.md,
                child: Row(
                  spacing: AppSpacing.flowTopBar,
                  children: [
                    InkWell(
                      onTap: onLogo,
                      child: const WyrmLogo(showStudio: false),
                    ),
                    Expanded(
                      child: Row(
                        spacing: AppSpacing.sm,
                        children: [
                          if (crumbs.isNotEmpty)
                            Button.quiet(
                              key: const ValueKey('flow-back'),
                              label: S.current.flowBack,
                              size: ButtonSize.small,
                              onPressed: () => onBack?.call(1),
                            ),
                          InkWell(
                            onTap: onFlows,
                            child: Text(
                              S.current.wsFlows,
                              style: TextStyle(
                                fontSize: FontSizes.lg,
                                color: c.text3,
                              ),
                            ),
                          ),
                          Text('›', style: TextStyle(color: c.muted)),
                          Flexible(
                            child: InkWell(
                              onTap: crumbs.isEmpty
                                  ? null
                                  : () => onBack?.call(crumbs.length),
                              child: Text(
                                flowLabel,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: mono(
                                  size: FontSizes.lg,
                                  color: crumbs.isEmpty ? c.text1 : c.text3,
                                ),
                              ),
                            ),
                          ),
                          for (final (i, name) in crumbs.indexed) ...[
                            Text('›', style: TextStyle(color: c.muted)),
                            Flexible(
                              child: InkWell(
                                onTap: i == crumbs.length - 1
                                    ? null
                                    : () => onBack?.call(crumbs.length - 1 - i),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: mono(
                                    size: FontSizes.lg,
                                    color: i == crumbs.length - 1
                                        ? c.text1
                                        : c.text3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (blockLabel case final b?) ...[
                            Text('›', style: TextStyle(color: c.muted)),
                            Flexible(
                              child: Text(
                                b,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: mono(
                                  size: FontSizes.lg,
                                  color: c.emberSoft,
                                ),
                              ),
                            ),
                          ],
                          if (instances case final n?)
                            Flexible(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: AppSpacing.sm,
                                ),
                                child: Text(
                                  S.current.instancesInFlow(n),
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: TextStyle(
                                    fontSize: FontSizes.sm,
                                    color: c.text4,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      spacing: AppSpacing.flowTopBarActions,
                      children: [
                        Row(
                          spacing: AppSpacing.flowRowParts,
                          children: [
                            if (stateDot)
                              Container(
                                width: AppSizes.flowDot,
                                height: AppSizes.flowDot,
                                decoration: BoxDecoration(
                                  shape: .circle,
                                  color: c.good,
                                ),
                              ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: AppSizes.flowStateText,
                              ),
                              child: Text(
                                status.label(version),
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(
                                  fontSize: FontSizes.sm,
                                  color: c.text4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Button.secondary(
                          label: S.current.validate,
                          onPressed: onValidate,
                        ),
                        if (deployOn)
                          Button.primary(
                            label: S.current.deploy,
                            onPressed: onDeploy,
                          )
                        else
                          Button.secondary(
                            label: S.current.deploy,
                            disabledReason: deployOff?.text,
                            onPressed: null,
                          ),
                        IconButton(
                          onPressed: onClose,
                          icon: AppIcon(
                            'ui_close',
                            size: AppSizes.flowEditorClose,
                            color: c.text2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _panels(context, deployOn)),
                  if (viewer case final v?)
                    Positioned.fill(
                      child: ValueViewer(
                        key: const ValueKey('value-viewer'),
                        vm: v,
                        onClose: onCloseViewer ?? () {},
                        onSave: onSaveViewer,
                        validate: validateViewer,
                        tables: viewerTables,
                        copyLabel: S.current.copyValue,
                        copiedLabel: S.current.copiedValue,
                        closeLabel: S.current.closeLabel,
                        editLabel: S.current.viewerEdit,
                        saveLabel: S.current.viewerSave,
                        cancelLabel: S.current.cancel,
                        saveHint: S.current.viewerSaveHint(
                          (mac ?? flowOnMac) ? 'Cmd+Enter' : 'Ctrl+Enter',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A command of the canvas: the page's own two, the rest to the
  /// connector.
  Future<void> _command(
    BuildContext context,
    FlowCommand command, {
    required bool deployOn,
    Offset? at,
  }) async {
    if (command == FlowCommand.searchPalette) {
      paletteSearchRequest.value++;
    } else if (command == FlowCommand.createCustomBlock) {
      // Name the block and its ports, then the selection becomes one.
      final vm = createBlock?.ask(null);
      if (vm == null) {
        return;
      }
      final check = checkBlock;
      final made = await CustomBlockDialog.ask(
        context,
        vm: vm,
        validate: check == null ? null : (r) => check.ask(r)?.label,
      );
      if (made != null) {
        onCreateBlock?.call(made);
      }
    } else if (command != FlowCommand.deploy) {
      onCommand?.call(command, at: at);
    } else if (deployOn) {
      final yes = await ConfirmDialog.ask(
        context,
        title: S.current.deployAskTitle,
        message: S.current.deployAskMessage(_flowLabel),
        confirm: S.current.deploy,
        cancel: S.current.cancel,
        danger: false,
      );
      if (yes) {
        onDeploy?.call();
      }
    }
  }

  Widget _panels(BuildContext context, bool deployOn) => SidePanels(
    onChanged: onPanelWidth,
    left: SidePanel(
      width: panels.left,
      defaultWidth: AppSizes.flowPalette,
      child: BlockPalette(
        tab: paletteTab,
        onTab: onPaletteTab,
        entries: palette,
        myBlocksOff: myBlocksOff,
        closed: paletteClosed,
        tree: tree,
        onTreeToggle: onTreeToggle,
        onQuery: onTreeQuery,
        checkName: switch (checkBlockName) {
          final q? => (name) => q.ask(name)?.label,
          null => null,
        },
      ),
    ),
    center: FaultBoundary(
      panel: .canvas,
      child: FlowCanvas(
        blocks: blocks,
        wires: wires,
        actions: blockActions,
        onClear: onClear,
        onMove: onMove,
        legend: true,
        // A flow, or a block opened inside it, fits the view when it opens.
        view: [_flowLabel, ...crumbs].join('/'),
        onSelectMany: onSelectMany,
        onCommand: (command, {at}) => unawaited(
          _command(context, command, deployOn: deployOn, at: at),
        ),
        menu: menu,
        onPin: onPin,
        onViewField: onViewField,
        prompt: prompt,
        onPromptSave: onPromptSave,
        onPromptCancel: onPromptCancel,
        validatePrompt: switch (checkScope) {
          final q? => (scope) => q.ask(scope)?.label,
          null => null,
        },
      ),
    ),
    right: SidePanel(
      width: panels.right,
      defaultWidth: AppSizes.flowInspector,
      child: FieldInspector(
        header: switch (nameField) {
          final f? => Padding(
            padding: Insets.flowInspectorName,
            child: ParamField(vm: f),
          ),
          null => null,
        },
        kindLabel: inspectorKind,
        title: inspectorTitle,
        note: inspectorNote,
        rows: inspectorRows,
        summary: summary,
        footer: [S.current.flowPropertiesNote, S.current.flowPropertiesNote2],
        onChanged: onFieldChanged,
        onUnbind: onFieldUnbind,
        onBind: onFieldBind,
        onProblem: onProblem,
        onGoToSource: onGoToSource,
        unbindLabel: S.current.unbind,
        goToSourceLabel: S.current.goToSource,
        boundLabel: S.current.boundMark,
        suggestLabel: S.current.suggestPick,
        removeLabel: S.current.removeBlock,
        onRemove: onRemove,
        onView: onView,
        viewLabel: S.current.viewValue,
        onPin: onFieldPin,
        pinLabel: S.current.pinField,
        unpinLabel: S.current.unpinField,
        pinLockedLabel: S.current.pinLocked,
        onRun: onRun,
        links: [
          if (onOpenInside case final open?) (S.current.openInside, open),
        ],
        confirmLabel: S.current.turnOn,
        cancelLabel: S.current.cancel,
      ),
    ),
  );

  /// The logo: to Explorer (spec §1).
  final VoidCallback onLogo;

  /// The palette and inspector widths the viewer chose (spec §1).
  final SidePanelWidths panels;
  final PanelResized? onPanelWidth;
}
