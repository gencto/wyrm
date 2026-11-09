import 'dart:async';

import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/side_panels.dart';
import '../flows/block_palette.dart';
import '../flows/field_inspector.dart';
import '../flows/flow_block_view.dart';
import '../flows/flow_canvas.dart';
import '../flows/flow_legend.dart';
import '../flows/flow_menu.dart';
import '../flows/shortcut_card.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../overlays/confirm_dialog.dart';
import '../overlays/value_viewer.dart';
import '../shell/window_bar.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

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
    super.key,
  });

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
                          InkWell(
                            onTap: onFlows,
                            child: Text(
                              flowsLabel,
                              style: TextStyle(fontSize: 14, color: c.text3),
                            ),
                          ),
                          Text('›', style: TextStyle(color: c.muted)),
                          Flexible(
                            child: Text(
                              flowLabel,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: mono(size: 14, color: c.text1),
                            ),
                          ),
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
      ),
    ),
    center: FlowCanvas(
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
        removeLabel: removeLabel,
        onRemove: onRemove,
        onView: onView,
        viewLabel: viewLabel,
        onPin: onFieldPin,
        pinLabel: pinLabel,
        unpinLabel: unpinLabel,
        pinLockedLabel: pinLockedLabel,
      ),
    ),
  );

  /// The logo: to Explorer (spec §1).
  final void Function() onLogo;

  /// The palette and inspector widths the viewer chose (spec §1).
  final SidePanelWidths panels;
  final void Function(PanelSide side, double width)? onPanelWidth;
}
