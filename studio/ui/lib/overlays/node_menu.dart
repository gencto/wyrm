import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../theme/extensions/colors.dart';
import '../theme/typography.dart';

/// One item of a [NodeMenu]: an action of the node.
final class NodeMenuItemVm extends Equatable {
  const NodeMenuItemVm({
    required this.id,
    required this.label,
    this.level = '',
    this.danger = false,
    this.disabledReason,
  });

  /// The action's name, handed back when picked.
  final String id;

  /// Its display name, ending in `…` when it opens a form.
  final String label;

  /// `config`, `write`, `read`: the hint on the right.
  final String level;
  final bool danger;
  final String? disabledReason;

  @override
  List<Object?> get props => [id, label, level, danger, disabledReason];
}

/// A group of items under its header (the action `group`).
final class NodeMenuGroupVm extends Equatable {
  const NodeMenuGroupVm({required this.label, required this.items});

  final String label;
  final List<NodeMenuItemVm> items;

  @override
  List<Object?> get props => [label, items];
}

/// What a [NodeMenu] shows.
final class NodeMenuVm extends Equatable {
  const NodeMenuVm({
    required this.title,
    required this.subtitle,
    required this.groups,
    this.copyLabel = 'Copy key',
    this.copyShortcut = '⌘⇧C',
  });

  /// The node's name.
  final String title;

  /// `Modbus device · 7 actions`.
  final String subtitle;
  final List<NodeMenuGroupVm> groups;
  final String copyLabel;
  final String copyShortcut;

  @override
  List<Object?> get props => [
    title,
    subtitle,
    groups,
    copyLabel,
    copyShortcut,
  ];
}

/// The node menu of board *Explorer · Actions* (docs/design/specs/
/// explorer.md §5): 300 wide, radius 10, the node's name over its actions
/// grouped by `group`, each with its level on the right, danger items in
/// coral, and a footer row Copy key. [onPick] gets the action's id, or
/// [copyId] for the footer.
class NodeMenu extends StatelessWidget {
  const NodeMenu({required this.vm, required this.onPick, super.key});

  final NodeMenuVm vm;
  final ValueChanged<String> onPick;

  /// The id [onPick] gets for the footer row.
  static const copyId = '\u0000copy';

  /// Shows the menu at [at] (global) and returns what was picked.
  static Future<String?> show(
    BuildContext context, {
    required Offset at,
    required NodeMenuVm vm,
  }) => showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      return Stack(
        children: [
          Positioned(
            left: at.dx.clamp(8, size.width - 308),
            top: at.dy.clamp(8, size.height - 120),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height - 16),
              child: NodeMenu(
                vm: vm,
                onPick: (id) => Navigator.of(context).pop(id),
              ),
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(NodeMenuItemVm i) {
      final enabled = i.disabledReason == null;
      final row = InkWell(
        onTap: enabled ? () => onPick(i.id) : null,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i.label,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: !enabled
                        ? c.muted
                        : (i.danger ? c.badText : c.text1),
                  ),
                ),
              ),
              Text(i.level, style: TextStyle(fontSize: 12, color: c.text4)),
            ],
          ),
        ),
      );
      return enabled ? row : Tooltip(message: i.disabledReason, child: row);
    }

    return Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                child: Row(
                  spacing: 8,
                  children: [
                    Text(
                      vm.title,
                      style: mono(weight: .w600, color: c.text1),
                    ),
                    Flexible(
                      child: Text(
                        vm.subtitle,
                        overflow: .ellipsis,
                        style: TextStyle(fontSize: 12, color: c.text4),
                      ),
                    ),
                  ],
                ),
              ),
              for (final g in vm.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Text(
                    g.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: .w600,
                      letterSpacing: 0.66,
                      color: c.text4,
                    ),
                  ),
                ),
                for (final i in g.items) item(i),
              ],
              Divider(height: 13, color: c.line1),
              InkWell(
                onTap: () => onPick(copyId),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          vm.copyLabel,
                          style: TextStyle(fontSize: 13, color: c.text3),
                        ),
                      ),
                      Text(
                        vm.copyShortcut,
                        style: mono(size: 12, color: c.text4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
