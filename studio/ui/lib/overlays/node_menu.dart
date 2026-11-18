import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/level_badge.dart';
import '../models/disabled.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One item of a [NodeMenu]: an action of the node (its name), or another
/// pick (a poll rate); [id] is handed back when picked.
final class NodeMenuItemVm<T> extends Equatable {
  const NodeMenuItemVm({
    required this.id,
    required this.label,
    this.level,
    this.danger = false,
    this.disabled,
    this.code,
  });

  /// Handed back when picked.
  final T id;

  /// Its display name, ending in `…` when it opens a form.
  final String label;

  /// The level it needs: the hint on the right; null for a pick that is
  /// no action.
  final AccessLevel? level;
  final bool danger;
  final Disabled? disabled;

  /// The action's own name, in the item's tooltip when the label says it
  /// in other words.
  final String? code;

  @override
  List<Object?> get props => [id, label, level, danger, disabled, code];
}

/// A group of items under its header (the action `group`).
final class NodeMenuGroupVm<T> extends Equatable {
  const NodeMenuGroupVm({required this.label, required this.items});

  final String label;
  final List<NodeMenuItemVm<T>> items;

  @override
  List<Object?> get props => [label, items];
}

/// What a [NodeMenu] shows.
final class NodeMenuVm<T> extends Equatable {
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
  final List<NodeMenuGroupVm<T>> groups;
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
/// coral, and a footer row Copy key. [onPick] gets the place of the item
/// picked, or [MenuSpot.copy] for the footer ([show] turns it into the
/// item's id).
class NodeMenu<T> extends StatelessWidget {
  const NodeMenu({required this.vm, required this.onPick, super.key});

  final NodeMenuVm<T> vm;
  final ValueChanged<MenuSpot> onPick;

  /// Shows the menu at [at] (global) and returns what was picked; null when
  /// it closed without a pick.
  static Future<MenuPick<T>?> show<T>(
    BuildContext context, {
    required Offset at,
    required NodeMenuVm<T> vm,
  }) => showDialog<MenuPick<T>>(
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
              child: NodeMenu<T>(
                vm: vm,
                onPick: (spot) => Navigator.of(context).pop(switch (spot) {
                  MenuItemSpot(:final group, :final item) => ItemPicked(
                    vm.groups[group].items[item].id,
                  ),
                  MenuCopySpot() => CopyPicked<T>(),
                }),
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
    Widget item(int group, int index, NodeMenuItemVm<T> i) {
      final why = i.disabled?.text;
      final enabled = why == null;
      final row = InkWell(
        onTap: enabled ? () => onPick(MenuItemSpot(group, index)) : null,
        child: Container(
          height: 38,
          padding: Insets.menuItem,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: FontSizes.lg,
                    color: !enabled
                        ? c.muted
                        : (i.danger ? c.badText : c.text1),
                  ),
                ),
              ),
              Text(
                i.level?.label ?? '',
                style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
              ),
            ],
          ),
        ),
      );
      if (!enabled) {
        return Tooltip(message: why, child: row);
      }
      final code = i.code;
      return code == null || i.label.startsWith(code)
          ? row
          : Tooltip(
              message: code,
              waitDuration: const Duration(milliseconds: 600),
              child: row,
            );
    }

    return Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: AppSizes.menu,
        child: SingleChildScrollView(
          padding: Insets.menu,
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              Padding(
                padding: Insets.nodeMenuHead,
                child: Row(
                  spacing: 8,
                  children: [
                    // The name gives way first, the subtitle keeps its
                    // own share: both are user text and can be long.
                    Flexible(
                      flex: 3,
                      child: Tooltip(
                        message: vm.title,
                        waitDuration: const Duration(milliseconds: 600),
                        child: Text(
                          vm.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: mono(weight: .w600, color: c.text1),
                        ),
                      ),
                    ),
                    Flexible(
                      flex: 2,
                      child: Text(
                        vm.subtitle,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          fontSize: FontSizes.sm,
                          color: c.text4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final (gi, g) in vm.groups.indexed) ...[
                Padding(
                  padding: Insets.menuGroupTitle,
                  child: Text(
                    g.label.toUpperCase(),
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(
                      fontSize: FontSizes.xs,
                      fontWeight: .w600,
                      letterSpacing: Trackings.smallLabel,
                      color: c.text4,
                    ),
                  ),
                ),
                for (final (ii, i) in g.items.indexed) item(gi, ii, i),
              ],
              Divider(height: 13, color: c.line1),
              InkWell(
                onTap: () => onPick(MenuSpot.copy),
                child: Container(
                  height: 34,
                  padding: Insets.menuItem,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          vm.copyLabel,
                          style: TextStyle(
                            fontSize: FontSizes.md,
                            color: c.text3,
                          ),
                        ),
                      ),
                      Text(
                        vm.copyShortcut,
                        style: mono(size: FontSizes.sm, color: c.text4),
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

/// What was picked in a [NodeMenu].
sealed class MenuPick<T> {
  const MenuPick();
}

/// An item: its id.
final class ItemPicked<T> extends MenuPick<T> {
  const ItemPicked(this.id);

  final T id;
}

/// The footer row: Copy key.
final class CopyPicked<T> extends MenuPick<T> {
  const CopyPicked();
}

/// Where a pick in a [NodeMenu] was: an item, or the footer.
sealed class MenuSpot {
  const MenuSpot();

  /// The footer row.
  static const copy = MenuCopySpot();
}

/// The item [item] of the group [group].
final class MenuItemSpot extends MenuSpot {
  const MenuItemSpot(this.group, this.item);

  final int group;
  final int item;
}

/// The footer row: Copy key.
final class MenuCopySpot extends MenuSpot {
  const MenuCopySpot();
}
