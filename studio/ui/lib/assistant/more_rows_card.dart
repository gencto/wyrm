import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../models/value_changed.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'blocked.dart';
import 'task_badge.dart';

/// One row of [MoreRowsCardVm]: a node the same change may be made for.
final class MoreRowVm extends Equatable {
  const MoreRowVm({
    required this.key,
    required this.label,
    this.detail = '',
    this.ticked = false,
  });

  /// The full node key (sent as `context` when ticked).
  final String key;

  /// The model's words for it.
  final String label;
  final String detail;
  final bool ticked;

  @override
  List<Object?> get props => [key, label, detail, ticked];
}

/// What [MoreRowsCard] draws: one suggestion with rows.
final class MoreRowsCardVm extends Equatable {
  const MoreRowsCardVm({
    required this.id,
    required this.title,
    required this.rows,
    this.detail = '',
    this.blocked,
    this.unattended,
  });

  /// The suggestion's id.
  final String id;

  /// The model's words.
  final String title;
  final String detail;
  final List<MoreRowVm> rows;

  /// Why *Make a plan* cannot be pressed; null: it can.
  final Blocked? blocked;

  /// The agent's mode when a pick's plan may write without a person.
  final AgentModeVm? unattended;

  /// `Make a plan for 2 units`.
  String get button => S.current.moreButton(rows.where((r) => r.ticked).length);

  String? get disabledReason => blocked?.text;

  /// What the rows are, or the caution of the agent's mode.
  String get note => unattended?.caution ?? S.current.moreNote;

  @override
  List<Object?> get props => [id, title, detail, rows, blocked, unattended];
}

/// Board *AssistantDone*, *Same for more units?*: the nodes the model says
/// the same change fits, one tickable row each, and a button that asks for
/// one plan for the ticked ones. The rows are the model's: they are picked,
/// not edited.
class MoreRowsCard extends StatelessWidget {
  const MoreRowsCard({
    required this.vm,
    required this.onRow,
    required this.onAsk,
    super.key,
  });

  final MoreRowsCardVm vm;

  /// A row (by its key) was ticked or unticked.
  final Toggled<String> onRow;

  /// The button was pressed.
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(
      fontSize: FontSizes.sm,
      height: LineHeights.row,
      color: c.text3,
    );
    return Container(
      margin: Insets.assistantCard,
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border.all(color: c.line2),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: Insets.cardRow,
            child: Column(
              crossAxisAlignment: .start,
              spacing: 3,
              children: [
                Text(
                  vm.title,
                  style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
                ),
                if (vm.detail.isNotEmpty) Text(vm.detail, style: small),
              ],
            ),
          ),
          for (final r in vm.rows)
            Container(
              padding: const EdgeInsets.fromLTRB(
                6,
                2,
                14,
                2,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Row(
                spacing: 6,
                children: [
                  Checkbox(
                    value: r.ticked,
                    onChanged: (v) => onRow(r.key, on: v ?? false),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          r.label,
                          style: TextStyle(
                            fontSize: FontSizes.md,
                            color: c.text1,
                          ),
                        ),
                        SelectableText(
                          r.key,
                          style: mono(size: FontSizes.xs, color: c.text3),
                        ),
                      ],
                    ),
                  ),
                  if (r.detail.isNotEmpty)
                    Flexible(
                      child: Text(r.detail, style: small, textAlign: .right),
                    ),
                ],
              ),
            ),
          Container(
            padding: Insets.cardFoot,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(child: Text(vm.note, style: small)),
                Button.primary(
                  label: vm.button,
                  disabledReason: vm.disabledReason,
                  onPressed: vm.disabledReason == null ? onAsk : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
