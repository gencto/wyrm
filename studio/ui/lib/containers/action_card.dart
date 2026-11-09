import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/level_badge.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One action of a node, as Explorer's Actions tab shows it.
final class ActionCardVm extends Equatable {
  const ActionCardVm({
    required this.id,
    required this.title,
    required this.level,
    required this.detail,
    this.selected = false,
    this.disabledReason,
  });

  final String id;
  final String title;

  /// `read`, `write`, `config`.
  final String level;

  /// `4 parameters · returns rows`.
  final String detail;
  final bool selected;
  final String? disabledReason;

  @override
  List<Object?> get props => [
    id,
    title,
    level,
    detail,
    selected,
    disabledReason,
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
    final off = vm.disabledReason != null;
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
          padding: const EdgeInsets.all(14),
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
                        fontSize: 14,
                        fontWeight: .w600,
                        color: off ? c.text3 : c.text1,
                      ),
                    ),
                  ),
                  LevelBadge(level: vm.level),
                ],
              ),
              Text(
                vm.disabledReason ?? vm.detail,
                style: off
                    ? TextStyle(fontSize: 12, color: c.text4)
                    : mono(size: 11, color: c.text4),
              ),
            ],
          ),
        ),
      ),
    );
    return off ? Tooltip(message: vm.disabledReason, child: card) : card;
  }
}
