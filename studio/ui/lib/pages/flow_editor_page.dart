import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/fault_boundary.dart';
import '../containers/side_panels.dart';
import '../flows/block_palette.dart';
import '../flows/custom_block_dialog.dart';
import '../flows/field_inspector.dart';
import '../flows/flow_block_view.dart';
import '../flows/flow_canvas.dart';
import '../flows/flow_legend.dart';
import '../flows/flow_menu.dart';
import '../flows/scope_prompt.dart';
import '../flows/shortcut_card.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../overlays/confirm_dialog.dart';
import '../overlays/value_viewer.dart';
import '../shell/window_bar.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import '../trees/tree_row.dart';

/// Boards *Flow editor · fields, bindings, properties* and *· drag points
/// and actions from the tree* (studio/docs/design/specs/flow-editor.md): the
/// top bar (path, draft state, Validate, Deploy), the palette (Blocks, My
/// blocks, Tree), the canvas of fields and wires, and the inspector of the
/// selected block or of the flow.
class FlowEditorPage extends StatelessWidget {
  const FlowEditorPage({
    required this.flowsLabel,
    required this.flowLabel,
    required this.state,
    required this.validateLabel,
    required this.deployLabel,
    required this.onValidate,
    required this.onClose,
    required this.onFlows,
    required this.onLogo,
    required this.paletteTabs,
    required this.paletteTab,
    required this.onPaletteTab,
    required this.palette,
    required this.onPick,
    required this.blocks,
    required this.wires,
    required this.blockActions,
    required this.onClear,
    required this.onMove,
    required this.onDrop,
    required this.inspectorFooter,
    required this.onFieldChanged,
    required this.onFieldUnbind,
    required this.onFieldBind,
    required this.onProblem,
    this.blockLabel,
    this.stateDot = false,
    this.onDeploy,
    this.deployReason,
    this.searchHint = '',
    this.paletteNotes = const [],
    this.paletteClosed = const {},
    this.legend,
    this.nameField,
    this.inspectorKind = '',
    this.inspectorTitle = '',
    this.inspectorNote = '',
    this.inspectorRows = const [],
    this.summary,
    this.removeLabel = '',
    this.onRemove,
    this.panels = const SidePanelWidths(),
    this.onPanelWidth,
    this.onGoToSource,
    this.unbindLabel = 'Unbind',
    this.goToSourceLabel = 'Go to source',
    this.boundLabel = 'bound',
    this.suggestLabel = 'Choose a value',
    this.viewer,
    this.onView,
    this.onCloseViewer,
    this.viewLabel = 'View value',
    this.copyLabel = 'Copy',
    this.copiedLabel = 'Copied',
    this.closeLabel = 'Close',
    this.window = const WindowBarVm(),
    this.onSelectMany,
    this.onCommand,
    this.menu,
    this.onPin,
    this.onViewField,
    this.onFieldPin,
    this.pinLabel = 'Pin to block',
    this.unpinLabel = 'Unpin from block',
    this.pinLockedLabel = 'A bound field stays on the block',
    this.onSaveViewer,
    this.validateViewer,
    this.editLabel = 'Edit',
    this.saveLabel = 'Save',
    this.cancelLabel = 'Cancel',
    this.saveHint = '',
    this.deployAskTitle = 'Deploy this flow?',
    this.deployAskMessage = '',
    this.crumbs = const [],
    this.onBack,
    this.backLabel = 'Back',
    this.insideNote,
    this.tree,
    this.onTreeToggle,
    this.onTreeQuery,
    this.onPaletteMenu,
    this.paletteEmpty = '',
    this.writable = const {},
    this.readLabel = 'Read',
    this.writeLabel = 'Write',
    this.createBlock,
    this.validateBlock,
    this.onCreateBlock,
    this.onRenameBlock,
    this.validateBlockName,
    this.renameTitle = 'Rename',
    this.renameLabel = 'Rename',
    this.prompt,
    this.onPromptSave,
    this.onPromptCancel,
    this.validatePrompt,
    this.onRun,
    this.inspectorLinks = const [],
    this.confirmLabel = 'Turn on',
    super.key,
  });

  /// The custom blocks the canvas is inside of, outermost first (spec
  /// §20): the path reads `Flows › <flow> › <block> …`, each part a link
  /// back to its level; empty: the canvas shows the flow.
  final List<String> crumbs;

  /// Back by so many levels (`Back`: one; the flow's name: all).
  final ValueChanged<int>? onBack;
  final String backLabel;

  /// Said beside the path while inside a block (`2 instances in this
  /// flow`).
  final String? insideNote;

  /// The Tree tab's rows (spec §18); null on the other tabs.
  final List<TreeRowVm>? tree;
  final ValueChanged<String>? onTreeToggle;
  final ValueChanged<String>? onTreeQuery;

  /// An item of a palette entry's context menu. `rename` asks for the new
  /// name first and goes to [onRenameBlock].
  final void Function(String entry, String item)? onPaletteMenu;
  final String paletteEmpty;

  /// The `key:<point>` entries that may also be written: dropped on the
  /// canvas they ask `Read` or `Write` (Alt held: `Write` at once), and
  /// `Write` places `set:<point>`.
  final Set<String> writable;
  final String readLabel;
  final String writeLabel;

  /// What `Create custom block…` asks of the selection; null: nothing to
  /// make a block of.
  final CustomBlockDialogVm? Function()? createBlock;
  final String? Function(CustomBlockResult result)? validateBlock;
  final ValueChanged<CustomBlockResult>? onCreateBlock;

  /// `Rename` of a custom block of the palette: the entry, the new name.
  final void Function(String entry, String name)? onRenameBlock;
  final String? Function(String name)? validateBlockName;
  final String renameTitle;
  final String renameLabel;

  /// The scope asked of a key that got a wire (spec §17).
  final ScopePromptVm? prompt;
  final ValueChanged<String>? onPromptSave;
  final VoidCallback? onPromptCancel;
  final String? Function(String scope)? validatePrompt;

  /// The `Run` button of an inspector row (an unbound `Trigger`).
  final ValueChanged<String>? onRun;

  /// Link buttons above the inspector's rows (`Open inside`).
  final List<(String, VoidCallback)> inspectorLinks;
  final String confirmLabel;

  /// A marquee or Select all on the canvas.
  final void Function(
    Set<String> ids, {
    required bool add,
    required bool toggle,
  })?
  onSelectMany;

  /// A command of the canvas (copy, paste at `at`, delete, undo, …). The
  /// page itself answers two: `searchPalette` puts the cursor in the
  /// palette's search field, `deploy` asks first ([deployAskTitle]) and
  /// then calls [onDeploy].
  final void Function(FlowCommand command, {Offset? at})? onCommand;

  /// The context menu of a block, of the selection or of the canvas.
  final FlowMenuVm Function(Set<String> ids, String? block, String? row)? menu;

  /// A field pinned to its block or taken off it, from the context menu.
  final void Function(String block, String field, {required bool pinned})?
  onPin;

  /// `V` over a row of the canvas: opens its value in the viewer.
  final void Function(String block, String row)? onViewField;

  /// The pin of an inspector row (a field of the selected block).
  final void Function(String id, {required bool pinned})? onFieldPin;
  final String pinLabel;
  final String unpinLabel;
  final String pinLockedLabel;

  /// Save of the viewer's Edit mode: the editor's text.
  final ValueChanged<String>? onSaveViewer;

  /// What is wrong with a text typed in the viewer; null: it saves.
  final String? Function(String text)? validateViewer;
  final String editLabel;
  final String saveLabel;
  final String cancelLabel;
  final String saveHint;
  final String deployAskTitle;
  final String deployAskMessage;

  /// `Flows`, a link back to the list.
  final String flowsLabel;

  /// The flow id (or `New dataflow`).
  final String flowLabel;

  /// The selected block, if any.
  final String? blockLabel;

  /// `Draft saved`, `Version 4 · deployed`, `Deploying…`, a problem.
  final String state;

  /// A teal dot before [state] (a draft that differs from the deployed one).
  final bool stateDot;
  final String validateLabel;
  final String deployLabel;
  final VoidCallback onValidate;
  final VoidCallback onClose;
  final VoidCallback onFlows;
  final VoidCallback? onDeploy;

  /// Why Deploy is off (`Nothing to deploy`); null: it is on.
  final String? deployReason;

  final List<TabItemVm> paletteTabs;
  final String paletteTab;
  final ValueChanged<String> onPaletteTab;
  final List<PaletteEntryVm> palette;
  final ValueChanged<String> onPick;
  final String searchHint;
  final List<PaletteNoteVm> paletteNotes;

  /// Palette groups shown closed at first.
  final Set<String> paletteClosed;

  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final FlowBlockActions blockActions;
  final VoidCallback onClear;
  final void Function(Map<String, Offset> to, {required bool nudge}) onMove;
  final void Function(String entry, double x, double y) onDrop;
  final FlowLegendVm? legend;

  /// The id field of a new flow.
  final ParamFieldVm? nameField;
  final String inspectorKind;
  final String inspectorTitle;
  final String inspectorNote;
  final List<InspectorRowVm> inspectorRows;
  final FlowSummaryVm? summary;
  final List<String> inspectorFooter;
  final void Function(String id, String value) onFieldChanged;
  final ValueChanged<String> onFieldUnbind;
  final void Function(String id, FieldRefVm from) onFieldBind;
  final ValueChanged<String> onProblem;
  final String removeLabel;
  final VoidCallback? onRemove;

  /// `Go to source` of a bound field in the inspector: selects the block.
  final ValueChanged<String>? onGoToSource;
  final String unbindLabel;
  final String goToSourceLabel;
  final String boundLabel;

  /// The tooltip of the menu of a field with usual values (a time zone).
  final String suggestLabel;

  /// The open value viewer of a field, live; null: none is open.
  final ValueViewerVm? viewer;

  /// The eye of an inspector row (its id): opens the viewer.
  final ValueChanged<String>? onView;
  final VoidCallback? onCloseViewer;
  final String viewLabel;
  final String copyLabel;
  final String copiedLabel;
  final String closeLabel;

  /// The frameless window's side of the top bar (docs/studio.md §7.1).
  final WindowBarVm window;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final deployOn = deployReason == null && onDeploy != null;
    return Scaffold(
      backgroundColor: c.ground0,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: c.ground0,
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: WindowBar(
                vm: window,
                padding: 16,
                child: Row(
                  spacing: 18,
                  children: [
                    InkWell(
                      onTap: onLogo,
                      child: const WyrmLogo(showStudio: false),
                    ),
                    Expanded(
                      child: Row(
                        spacing: 8,
                        children: [
                          if (crumbs.isNotEmpty)
                            Button.quiet(
                              key: const ValueKey('flow-back'),
                              label: backLabel,
                              size: ButtonSize.small,
                              onPressed: () => onBack?.call(1),
                            ),
                          InkWell(
                            onTap: onFlows,
                            child: Text(
                              flowsLabel,
                              style: TextStyle(fontSize: 14, color: c.text3),
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
                                  size: 14,
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
                                    size: 14,
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
                                style: mono(size: 14, color: c.emberSoft),
                              ),
                            ),
                          ],
                          if (insideNote case final note?)
                            Flexible(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  note,
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.text4,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            if (stateDot)
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: .circle,
                                  color: c.good,
                                ),
                              ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Text(
                                state,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: TextStyle(fontSize: 12, color: c.text4),
                              ),
                            ),
                          ],
                        ),
                        Button.secondary(
                          label: validateLabel,
                          onPressed: onValidate,
                        ),
                        if (deployOn)
                          Button.primary(
                            label: deployLabel,
                            onPressed: onDeploy,
                          )
                        else
                          Button.secondary(
                            label: deployLabel,
                            disabledReason: deployReason,
                            onPressed: null,
                          ),
                        IconButton(
                          onPressed: onClose,
                          icon: AppIcon('ui_close', size: 18, color: c.text2),
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
                        copyLabel: copyLabel,
                        copiedLabel: copiedLabel,
                        closeLabel: closeLabel,
                        editLabel: editLabel,
                        saveLabel: saveLabel,
                        cancelLabel: cancelLabel,
                        saveHint: saveHint,
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
      final vm = createBlock?.call();
      if (vm == null) {
        return;
      }
      final made = await CustomBlockDialog.ask(
        context,
        vm: vm,
        validate: validateBlock,
      );
      if (made != null) {
        onCreateBlock?.call(made);
      }
    } else if (command != FlowCommand.deploy) {
      onCommand?.call(command, at: at);
    } else if (deployOn) {
      final yes = await ConfirmDialog.ask(
        context,
        title: deployAskTitle,
        message: deployAskMessage,
        confirm: deployLabel,
        cancel: cancelLabel,
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
      defaultWidth: 220,
      child: BlockPalette(
        tabs: paletteTabs,
        tab: paletteTab,
        onTab: onPaletteTab,
        entries: palette,
        onPick: onPick,
        hint: searchHint,
        notes: paletteNotes,
        closed: paletteClosed,
        tree: tree,
        onTreeToggle: onTreeToggle,
        onQuery: onTreeQuery,
        empty: paletteEmpty,
        onMenu: (entry, item) => unawaited(_paletteMenu(context, entry, item)),
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
        onDrop: onDrop,
        legend: legend,
        onSelectMany: onSelectMany,
        onCommand: (command, {at}) => unawaited(
          _command(context, command, deployOn: deployOn, at: at),
        ),
        menu: menu,
        onPin: onPin,
        onViewField: onViewField,
        dropChoice: _dropChoice,
        prompt: prompt,
        onPromptSave: onPromptSave,
        onPromptCancel: onPromptCancel,
        validatePrompt: validatePrompt,
      ),
    ),
    right: SidePanel(
      width: panels.right,
      defaultWidth: 320,
      child: FieldInspector(
        header: switch (nameField) {
          final f? => Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: ParamField(vm: f),
          ),
          null => null,
        },
        kindLabel: inspectorKind,
        title: inspectorTitle,
        note: inspectorNote,
        rows: inspectorRows,
        summary: summary,
        footer: inspectorFooter,
        onChanged: onFieldChanged,
        onUnbind: onFieldUnbind,
        onBind: onFieldBind,
        onProblem: onProblem,
        onGoToSource: onGoToSource,
        unbindLabel: unbindLabel,
        goToSourceLabel: goToSourceLabel,
        boundLabel: boundLabel,
        suggestLabel: suggestLabel,
        removeLabel: removeLabel,
        onRemove: onRemove,
        onView: onView,
        viewLabel: viewLabel,
        onPin: onFieldPin,
        pinLabel: pinLabel,
        unpinLabel: unpinLabel,
        pinLockedLabel: pinLockedLabel,
        onRun: onRun,
        links: inspectorLinks,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    ),
  );

  /// A palette entry let go on the canvas: a point that may be written
  /// asks `Read` or `Write` where it landed; Alt held writes at once.
  Future<String?> _dropChoice(
    BuildContext context,
    String entry,
    Offset at,
  ) async {
    if (!writable.contains(entry)) {
      return entry;
    }
    final write = 'set:${entry.substring(entry.indexOf(':') + 1)}';
    if (HardwareKeyboard.instance.isAltPressed) {
      return write;
    }
    final c = context.colors;
    return showMenu<String>(
      context: context,
      color: c.ground3,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        for (final (value, label) in [(entry, readLabel), (write, writeLabel)])
          PopupMenuItem(
            value: value,
            height: 34,
            child: Text(label, style: TextStyle(fontSize: 13, color: c.text1)),
          ),
      ],
    );
  }

  /// An item of a palette entry's menu: `rename` asks for the name first.
  Future<void> _paletteMenu(
    BuildContext context,
    String entry,
    String item,
  ) async {
    if (item != 'rename') {
      onPaletteMenu?.call(entry, item);
      return;
    }
    final name = await NameDialog.ask(
      context,
      title: renameTitle,
      value: entry.substring(entry.indexOf(':') + 1),
      confirm: renameLabel,
      cancel: cancelLabel,
      validate: validateBlockName,
    );
    if (name != null) {
      onRenameBlock?.call(entry, name);
    }
  }

  /// The logo: to Explorer (spec §1).
  final void Function() onLogo;

  /// The palette and inspector widths the viewer chose (spec §1).
  final SidePanelWidths panels;
  final void Function(PanelSide side, double width)? onPanelWidth;
}
