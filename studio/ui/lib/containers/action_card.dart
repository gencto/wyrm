import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/level_badge.dart';
import '../models/disabled.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One action of a node, as Explorer's Actions tab shows it.
final class ActionCardVm extends Equatable {
  const ActionCardVm({
    required this.id,
    required this.title,
    required this.level,
    required this.params,
    this.result,
    this.selected = false,
    this.disabled,
  });

  final String id;
  final String title;

  final AccessLevel level;

  /// How many parameters it takes; its result type, when it has one
  /// (`id · 4 parameters · returns rows`).
  final int params;
  final String? result;
  final bool selected;
  final Disabled? disabled;

  @override
  List<Object?> get props => [
    id,
    title,
    level,
    params,
    result,
    selected,
    disabled,
  ];
}

/// Board *Explorer · Actions of a node*: title, level badge, a mono line.
class ActionCard extends StatelessWidget {
  const ActionCard({required this.vm, this.onTap, super.key});

  final ActionCardVm vm;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final why = vm.disabled?.text;
    final off = why != null;
    final card = Material(
      color: vm.selected ? c.emberFill : c.ground2,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(
          color: vm.selected ? c.ember : c.line1,
          width: vm.selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(vm.id),
        borderRadius: Radii.card,
        child: Padding(
          padding: Insets.cardBody,
          child: Column(
            crossAxisAlignment: .start,
            spacing: 6,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vm.title,
                      maxLines: 2,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontSize: FontSizes.lg,
                        fontWeight: .w600,
                        color: off ? c.text3 : c.text1,
                      ),
                    ),
                  ),
                  LevelBadge.of(vm.level),
                ],
              ),
              Text(
                why ??
                    [
                      // The action's own name stays in reach (owner
                      // 2026-11-11).
                      vm.id,
                      S.current.paramCount(vm.params),
                      if (vm.result case final r?) S.current.returns(r),
                    ].join(' · '),
                style: off
                    ? TextStyle(fontSize: FontSizes.sm, color: c.text4)
                    : mono(size: FontSizes.xs, color: c.text4),
              ),
            ],
          ),
        ),
      ),
    );
    return off ? Tooltip(message: why, child: card) : card;
  }
}
