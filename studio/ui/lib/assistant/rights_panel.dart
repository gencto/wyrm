import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../containers/fact_grid.dart';
import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One mode of *Who approves*.
final class ModeVm extends Equatable {
  const ModeVm({
    required this.id,
    required this.label,
    required this.detail,
    this.selected = false,
  });

  /// `write`, `config`, `never` (the agent's `require_approval`).
  final String id;
  final String label;
  final String detail;
  final bool selected;

  @override
  List<Object?> get props => [id, label, detail, selected];
}

/// What [RightsPanel] draws.
final class RightsPanelVm extends Equatable {
  const RightsPanelVm({
    required this.modesLabel,
    required this.modes,
    required this.prefixesLabel,
    required this.prefixes,
    required this.prefixesNote,
    required this.facts,
    required this.note,
    this.editReason,
    this.addPrefix,
    this.staged,
  });

  /// `Who approves`.
  final String modesLabel;
  final List<ModeVm> modes;

  /// `Where it may propose changes`.
  final String prefixesLabel;

  /// The agent's `allowed_prefixes`: the full key and what is shown (below
  /// the site).
  final List<(String, String)> prefixes;
  final String prefixesNote;

  /// `+ prefix`; null: not offered.
  final String? addPrefix;

  /// Model, Today, API key, Sent to.
  final List<FactVm> facts;
  final String note;

  /// Why the modes and prefixes cannot be changed (no config on the
  /// agent link); null: a pick stages an update of its params.
  final String? editReason;

  /// A change of the params is staged: it runs when Review applies it.
  final String? staged;

  @override
  List<Object?> get props => [
    modesLabel,
    modes,
    prefixesLabel,
    prefixes,
    prefixesNote,
    addPrefix,
    facts,
    note,
    editReason,
    staged,
  ];
}

/// Board *AssistantRights*: who approves (the three modes), where the agent
/// may propose changes (prefix chips), the model, today's budget, the API
/// key (set or not, never shown) and where it is sent. A pick stages an
/// update of the agent link's params; Review applies it.
class RightsPanel extends StatelessWidget {
  const RightsPanel({
    required this.vm,
    this.onMode,
    this.onRemovePrefix,
    this.onAddPrefix,
    super.key,
  });

  final RightsPanelVm vm;
  final ValueChanged<String>? onMode;
  final ValueChanged<String>? onRemovePrefix;
  final VoidCallback? onAddPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 11, height: 1.4, color: c.text3);
    final can = vm.editReason == null;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        SectionLabel(vm.modesLabel),
        for (final m in vm.modes)
          Tooltip(
            message: vm.editReason ?? '',
            child: Material(
              color: m.selected ? c.emberTint : Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: m.selected ? c.ember : c.line1,
                  width: m.selected ? 1.5 : 1,
                ),
                borderRadius: Radii.control,
              ),
              child: InkWell(
                onTap: can && !m.selected && onMode != null
                    ? () => onMode!(m.id)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: .start,
                    spacing: 10,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: .circle,
                          border: Border.all(
                            color: m.selected ? c.ember : c.text4,
                            width: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          spacing: 2,
                          children: [
                            Text(
                              m.label,
                              style: TextStyle(fontSize: 13, color: c.text1),
                            ),
                            Text(m.detail, style: small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        SectionLabel(vm.prefixesLabel),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: .center,
          children: [
            for (final (p, label) in vm.prefixes)
              Container(
                height: 24,
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.only(left: 8, right: 2),
                decoration: BoxDecoration(
                  color: c.ground3,
                  border: Border.all(color: c.line2),
                  borderRadius: Radii.chip,
                ),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: p,
                        child: Text(
                          label,
                          overflow: .ellipsis,
                          style: mono(size: 11, color: c.text1),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: vm.editReason ?? '',
                      child: InkWell(
                        onTap: can && onRemovePrefix != null
                            ? () => onRemovePrefix!(p)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: AppIcon(
                            'ui_close',
                            size: 11,
                            color: can ? c.text3 : c.text4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (vm.addPrefix case final a?)
              Tooltip(
                message: vm.editReason ?? '',
                child: InkWell(
                  onTap: can ? onAddPrefix : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      a,
                      style: TextStyle(
                        fontSize: 12,
                        color: can ? c.text2 : c.text4,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Text(vm.prefixesNote, style: small),
        if (vm.staged case final s?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.warnTint,
              border: Border.all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Text(s, style: small.copyWith(color: c.warn)),
          ),
        const SizedBox(height: 10),
        FactGrid(facts: vm.facts, labelWidth: 96),
        Text(vm.note, style: small),
      ],
    );
  }
}
