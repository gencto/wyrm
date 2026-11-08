import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/section_label.dart';
import '../flows/block_palette.dart';
import '../flows/flow_canvas.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../shell/wyrm_logo.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// Board *Flow editor · fields, bindings, properties*: the palette (Blocks,
/// Tree), the canvas, the properties of the selected block; Validate and
/// Deploy in the top bar, the engine's answer beside them.
class FlowEditorPage extends StatelessWidget {
  const FlowEditorPage({
    required this.crumbs,
    required this.status,
    required this.statusTone,
    required this.validateLabel,
    required this.deployLabel,
    required this.paletteTabs,
    required this.paletteTab,
    required this.onPaletteTab,
    required this.palette,
    required this.onPick,
    required this.blocks,
    required this.wires,
    required this.onSelect,
    required this.onMove,
    required this.onConnect,
    required this.onDisconnect,
    required this.onDrop,
    required this.onClose,
    required this.onValidate,
    required this.propertiesTitle,
    required this.propertiesNote,
    this.searchHint = '',
    this.onDeploy,
    this.deployReason,
    this.nameField,
    this.selectedTitle,
    this.selectedType,
    this.selectedDescription,
    this.fields = const [],
    this.bindings = const [],
    this.onRemove,
    this.removeLabel = 'Remove block',
    super.key,
  });

  /// `Flows › tank-level › case`.
  final List<String> crumbs;
  final String status;
  final Tone statusTone;
  final String validateLabel;
  final String deployLabel;
  final List<TabItemVm> paletteTabs;
  final String paletteTab;
  final ValueChanged<String> onPaletteTab;
  final List<PaletteEntryVm> palette;
  final ValueChanged<String> onPick;
  final String searchHint;
  final List<FlowBlockVm> blocks;
  final List<FlowWireVm> wires;
  final ValueChanged<String?> onSelect;
  final void Function(String id, double x, double y) onMove;
  final void Function(String a, String ap, String b, String bp) onConnect;
  final void Function(String to, String toPort) onDisconnect;
  final void Function(String entry, double x, double y) onDrop;
  final VoidCallback onClose;
  final VoidCallback onValidate;
  final VoidCallback? onDeploy;
  final String? deployReason;

  /// The id field of a new flow.
  final ParamFieldVm? nameField;
  final String propertiesTitle;
  final String propertiesNote;
  final String? selectedTitle;
  final String? selectedType;
  final String? selectedDescription;
  final List<ParamFieldVm> fields;

  /// `input ← tankInfo.state`: what is wired into the block.
  final List<(String, String)> bindings;
  final VoidCallback? onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.ground0,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 14,
                children: [
                  const WyrmLogo(showStudio: false),
                  for (final (i, cr) in crumbs.indexed) ...[
                    if (i > 0) Text('›', style: TextStyle(color: c.text4)),
                    Text(
                      cr,
                      style: TextStyle(
                        fontSize: 14,
                        color: i == crumbs.length - 1
                            ? c.emberSoft
                            : (i == 0 ? c.text3 : c.text1),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Flexible(
                    child: QualityMark(
                      vm: QualityMarkVm(label: status, tone: statusTone),
                      size: 12,
                    ),
                  ),
                  Button.secondary(label: validateLabel, onPressed: onValidate),
                  Button.primary(
                    label: deployLabel,
                    disabledReason: deployReason,
                    onPressed: deployReason == null ? onDeploy : null,
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: AppIcon('ui_close', size: 18, color: c.text2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  BlockPalette(
                    tabs: paletteTabs,
                    tab: paletteTab,
                    onTab: onPaletteTab,
                    entries: palette,
                    onPick: onPick,
                    hint: searchHint,
                  ),
                  Expanded(
                    child: FlowCanvas(
                      blocks: blocks,
                      wires: wires,
                      onSelect: onSelect,
                      onMove: onMove,
                      onConnect: onConnect,
                      onDisconnect: onDisconnect,
                      onDrop: onDrop,
                    ),
                  ),
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: c.ground1,
                      border: Border(left: BorderSide(color: c.line1)),
                    ),
                    child: Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(18),
                            children: [
                              if (nameField case final f?) ...[
                                ParamField(vm: f),
                                const SizedBox(height: 18),
                              ],
                              SectionLabel(propertiesTitle),
                              const SizedBox(height: 6),
                              if (selectedTitle case final t?) ...[
                                Text(
                                  t,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (selectedType case final ty?)
                                  Text(
                                    ty,
                                    style: mono(size: 12, color: c.text4),
                                  ),
                                if (selectedDescription case final d?) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    d,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.text3,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                for (final (port, src) in bindings)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            port,
                                            style: mono(
                                              size: 12,
                                              color: c.text3,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '← $src',
                                          style: mono(size: 12, color: c.good),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (bindings.isNotEmpty)
                                  const SizedBox(height: 10),
                                ParamForm(
                                  key: ValueKey(selectedTitle),
                                  fields: fields,
                                ),
                                const SizedBox(height: 18),
                                Button.danger(
                                  label: removeLabel,
                                  onPressed: onRemove,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: c.line1)),
                          ),
                          child: Text(
                            propertiesNote,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: c.text3,
                            ),
                          ),
                        ),
                      ],
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
}
