import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

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
    required this.button,
    this.detail = '',
    this.disabledReason,
    this.note,
  });

  /// The suggestion's id in its task.
  final String id;

  /// The suggestion's label (`Same for more units?`), as the model wrote it.
  final String title;
  final String detail;
  final List<MoreRowVm> rows;

  /// `Make a plan for 2 units`.
  final String button;

  /// Why the button is off (no row ticked, rights, an ask in flight).
  final String? disabledReason;

  /// The line under the button.
  final String? note;

  @override
  List<Object?> get props => [
    id,
    title,
    detail,
    rows,
    button,
    disabledReason,
    note,
  ];
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
  final void Function(String key, {required bool on}) onRow;

  /// The button was pressed.
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, height: 1.45, color: c.text3);
    return Container(
      margin: const EdgeInsets.only(left: 42, bottom: 12),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 3,
              children: [
                Text(vm.title, style: TextStyle(fontSize: 14, color: c.text1)),
                if (vm.detail.isNotEmpty) Text(vm.detail, style: small),
              ],
            ),
          ),
          for (final r in vm.rows)
            Container(
              padding: const EdgeInsets.fromLTRB(6, 2, 14, 2),
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
                          style: TextStyle(fontSize: 13, color: c.text1),
                        ),
                        SelectableText(
                          r.key,
                          style: mono(size: 11, color: c.text3),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line1)),
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: vm.note == null
                      ? const SizedBox.shrink()
                      : Text(vm.note!, style: small),
                ),
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
