import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One row of [RowList].
final class RowItemVm extends Equatable {
  const RowItemVm({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.trailing = '',
    this.action,
    this.actionHint,
    this.actionReason,
  });

  final String id;

  /// A name, set in mono.
  final String title;
  final String subtitle;

  /// A short fact at the right (`not connected`, `48 points`).
  final String trailing;

  /// The label of the row's button (`Remove`), or none.
  final String? action;

  /// What the button does, for assistive technology
  /// (`Remove profile abb:m4m-30`).
  final String? actionHint;

  /// Why the button is disabled; enabled when null.
  final String? actionReason;

  @override
  List<Object?> get props => [
    id,
    title,
    subtitle,
    trailing,
    action,
    actionHint,
    actionReason,
  ];
}

/// A short boxed list of named things, each with a fact and at most one
/// button (board `SystemMaint`: the disconnected links, the profiles). With
/// no rows it says [empty].
class RowList extends StatelessWidget {
  const RowList({
    required this.rows,
    this.onAction,
    this.empty = '',
    this.emptyBad = false,
    super.key,
  });

  final List<RowItemVm> rows;

  /// The button of a row was pressed; the row's id.
  final ValueChanged<String>? onAction;
  final String empty;
  final bool emptyBad;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        border: .all(color: c.line1),
        borderRadius: Radii.control,
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                empty,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: emptyBad ? c.text3 : c.text4,
                ),
              ),
            ),
          for (final (i, r) in rows.indexed)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: r.action == null ? 10 : 8,
              ),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: c.ground3)),
              ),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 2,
                      children: [
                        Text(
                          r.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 13,
                            color: c.text1,
                          ),
                        ),
                        if (r.subtitle.isNotEmpty)
                          Text(
                            r.subtitle,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: TextStyle(fontSize: 12, color: c.text4),
                          ),
                      ],
                    ),
                  ),
                  if (r.trailing.isNotEmpty)
                    Text(
                      r.trailing,
                      style: TextStyle(fontSize: 12, color: c.text4),
                    ),
                  if (r.action case final a?) _button(c, r, a),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _button(AppColors c, RowItemVm r, String label) {
    final enabled = r.actionReason == null && onAction != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: r.actionHint ?? label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.segment,
          side: BorderSide(color: c.line1),
        ),
        child: InkWell(
          onTap: enabled ? () => onAction!(r.id) : null,
          borderRadius: Radii.segment,
          hoverColor: c.text1.withValues(alpha: 0.05),
          child: Container(
            height: 30,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? c.text3 : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
    return switch (r.actionReason) {
      final reason? => Tooltip(message: reason, child: button),
      null => button,
    };
  }
}
