import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../indicators/quality_mark.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One row of the tree.
final class TreeRowVm extends Equatable {
  const TreeRowVm({
    required this.id,
    required this.name,
    required this.depth,
    this.icon = 'node_section',
    this.hasChildren = false,
    this.expanded = false,
    this.selected = false,
    this.staged = false,
    this.chip,
    this.dot,
    this.dotLabel,
    this.meta,
    this.hasHistory = false,
    this.marked = false,
  });

  /// The node's key.
  final String id;
  final String name;
  final int depth;

  /// A `node_` icon.
  final String icon;

  /// A child node exists (spec 02 `has_nodes`): the triangle.
  final bool hasChildren;
  final bool expanded;
  final bool selected;

  /// An ember dot: a change waits to be applied.
  final bool staged;

  /// A run mode tag (`Process`).
  final String? chip;

  /// A state dot and its word (tooltip).
  final Tone? dot;
  final String? dotLabel;

  /// Right-aligned grey text: a count, `draft`.
  final String? meta;

  /// The point has a history store.
  final bool hasHistory;

  /// Added to the selection for Copy keys (⌘/Shift-click).
  final bool marked;

  @override
  List<Object?> get props => [
    id,
    name,
    depth,
    icon,
    hasChildren,
    expanded,
    selected,
    staged,
    chip,
    dot,
    dotLabel,
    meta,
    hasHistory,
    marked,
  ];
}

/// 40 high (32 compact), indented 10 + 16 per level, radius 6: chevron 14,
/// the kind icon 16 (`AppIcon.nodeName`), the name in mono 13, then the run
/// mode chip, the meta and the state dot 8 (docs/design/specs/explorer.md
/// §2). Selected is the ember tint with the icon in ember and the name in
/// 600.
class TreeRow extends StatelessWidget {
  const TreeRow({
    required this.vm,
    this.onTap,
    this.onToggle,
    this.onMore,
    this.height = 40,
    super.key,
  });

  final TreeRowVm vm;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onToggle;

  /// The `⋯` button of the selected row: the node menu at that point.
  final void Function(String id, Offset at)? onMore;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = vm.selected;
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(vm.id),
      borderRadius: Radii.segment,
      hoverColor: c.ground3,
      child: Container(
        height: height,
        padding: EdgeInsets.only(left: 10.0 + vm.depth * 16, right: 10),
        decoration: BoxDecoration(
          color: sel ? c.emberTint : (vm.marked ? c.ground3 : null),
          borderRadius: Radii.segment,
        ),
        child: Row(
          spacing: 8,
          children: [
            SizedBox(
              width: 16,
              child: vm.hasChildren
                  ? GestureDetector(
                      onTap: onToggle == null ? null : () => onToggle!(vm.id),
                      child: AnimatedRotation(
                        turns: vm.expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: AppIcon(
                          'ui_chevron_right',
                          size: 14,
                          color: c.text4,
                        ),
                      ),
                    )
                  : null,
            ),
            AppIcon(vm.icon, size: 16, color: sel ? c.ember : c.text4),
            Expanded(
              child: Text(
                vm.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: mono(
                  weight: sel ? .w600 : .w400,
                  color: sel ? c.text1 : c.text2,
                ),
              ),
            ),
            if (vm.staged)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: .circle, color: c.ember),
              ),
            if (vm.hasHistory) AppIcon('action_hist', size: 14, color: c.text4),
            if (vm.chip case final chip?) _Chip(chip),
            if (vm.meta case final m?)
              Text(m, style: TextStyle(fontSize: 12, color: c.text4)),
            if (vm.dot case final t?)
              Tooltip(
                message: vm.dotLabel ?? '',
                child: StateMark(mark: Mark.dot, color: toneColor(c, t)),
              ),
            if (sel && onMore != null)
              GestureDetector(
                onTapUp: (d) => onMore!(vm.id, d.globalPosition),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: Color.lerp(c.emberTint, c.emberLine, 0.35),
                    borderRadius: Radii.segment,
                  ),
                  child: AppIcon('ui_more', size: 16, color: c.emberSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The run mode of a link row: 11, padding 2 × 6, radius 4, ground/4 with
/// text/3: smaller than the shared tag chip, to sit in a 40 row.
class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.ground4, borderRadius: Radii.chip),
      child: Text(label, style: TextStyle(fontSize: 11, color: c.text3)),
    );
  }
}
