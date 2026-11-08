import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

/// One workspace of the rail.
final class RailItemVm extends Equatable {
  const RailItemVm({required this.icon, required this.label, this.badge});

  /// A `ws_` icon.
  final String icon;
  final String label;

  /// A count to call out (Quarantine waiting, tasks to approve).
  final String? badge;

  @override
  List<Object?> get props => [icon, label, badge];
}

/// The 76 px rail: icon over label, the current one on ground/4; the last
/// item (System) sits at the bottom.
class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<RailItemVm> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(int i) {
      final it = items[i];
      final on = i == selected;
      return Tooltip(
        message: it.label,
        waitDuration: const Duration(milliseconds: 800),
        child: InkWell(
          onTap: () => onSelect(i),
          borderRadius: Radii.control,
          child: Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.ground4 : null,
              borderRadius: Radii.control,
            ),
            child: Column(
              spacing: 4,
              children: [
                Badge(
                  isLabelVisible: it.badge != null,
                  label: Text(it.badge ?? ''),
                  backgroundColor: c.warn,
                  textColor: c.ground0,
                  child: AppIcon(it.icon, color: on ? c.text1 : c.text3),
                ),
                Text(
                  it.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: on ? c.text1 : c.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.ground0,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: Column(
        spacing: 4,
        children: [
          for (var i = 0; i < items.length - 1; i++) item(i),
          const Spacer(),
          if (items.isNotEmpty) item(items.length - 1),
        ],
      ),
    );
  }
}

/// Below 800 px: the first [visible] workspaces as a bottom bar and a More
/// sheet for the rest.
class WorkspaceBottomBar extends StatelessWidget {
  const WorkspaceBottomBar({
    required this.items,
    required this.selected,
    required this.onSelect,
    this.visible = 4,
    this.more = 'More',
    super.key,
  });

  final List<RailItemVm> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final int visible;
  final String more;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inMore = selected >= visible;
    return NavigationBar(
      height: 64,
      backgroundColor: c.ground0,
      indicatorColor: c.ground4,
      selectedIndex: inMore ? visible : selected,
      labelBehavior: .alwaysShow,
      onDestinationSelected: (i) async {
        if (i < visible) {
          onSelect(i);
          return;
        }
        final picked = await showModalBottomSheet<int>(
          context: context,
          backgroundColor: c.ground1,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: .min,
              children: [
                for (var j = visible; j < items.length; j++)
                  ListTile(
                    leading: AppIcon(items[j].icon, color: c.text2),
                    title: Text(items[j].label),
                    selected: j == selected,
                    onTap: () => Navigator.of(context).pop(j),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) {
          onSelect(picked);
        }
      },
      destinations: [
        for (var i = 0; i < visible && i < items.length; i++)
          NavigationDestination(
            icon: AppIcon(items[i].icon, color: c.text3),
            selectedIcon: AppIcon(items[i].icon, color: c.text1),
            label: items[i].label,
          ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz, color: c.text3),
          label: more,
        ),
      ],
    );
  }
}
