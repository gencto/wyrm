import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/side_panels.dart';
import '../flows/block_palette.dart';
import '../flows/field_inspector.dart';
import '../flows/flow_block_view.dart';
import '../flows/flow_canvas.dart';
import '../flows/flow_legend.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
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
    super.key,
  });

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
  final void Function(String id, double x, double y) onMove;
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: c.ground0,
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
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
                        Button.primary(label: deployLabel, onPressed: onDeploy)
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
            Expanded(
              child: SidePanels(
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
                    removeLabel: removeLabel,
                    onRemove: onRemove,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The logo: to Explorer (spec §1).
  final void Function() onLogo;

  /// The palette and inspector widths the viewer chose (spec §1).
  final SidePanelWidths panels;
  final void Function(PanelSide side, double width)? onPanelWidth;
}
