import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/segmented_tabs.dart';
import '../charts/trend.dart';
import '../containers/detail_inspector.dart';
import '../containers/section_label.dart';
import '../containers/side_panels.dart';
import '../models/value_changed.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One watch group in the left list.
final class GroupItemVm extends Equatable {
  const GroupItemVm({
    required this.id,
    required this.title,
    required this.sub,
    this.selected = false,
  });

  final String id;
  final String title;
  final String sub;
  final bool selected;

  @override
  List<Object?> get props => [id, title, sub, selected];
}

/// Board *History · watch groups and trends*: the groups, the selected
/// group's points, the trend of the points picked (none until the user
/// picks one), the group's settings and actions.
class HistoryPage extends StatelessWidget {
  const HistoryPage({
    required this.groupsLabel,
    required this.groups,
    required this.onGroup,
    required this.onAddGroup,
    required this.ranges,
    required this.range,
    required this.onRange,
    required this.trend,
    required this.trendEmpty,
    required this.onTrendWindow,
    required this.pointsLabel,
    required this.columns,
    required this.points,
    required this.onPoint,
    required this.onAction,
    this.addReason,
    this.title,
    this.subtitle,
    this.empty = '',
    this.pointsEmpty,
    this.pointsHint,
    this.footer,
    this.inspector,
    this.panels = const SidePanelWidths(),
    this.onPanelWidth,
    this.onTrendToggle,
    this.onTrendReset,
    super.key,
  });

  final String groupsLabel;
  final List<GroupItemVm> groups;
  final ValueChanged<String> onGroup;
  final VoidCallback onAddGroup;
  final String? addReason;
  final String? title;
  final String? subtitle;
  final String empty;
  final List<TabItemVm> ranges;
  final String range;
  final ValueChanged<String> onRange;

  /// The picked points' trend; null while none is picked.
  final TrendVm? trend;

  /// Shown in place of the trend while no point is picked.
  final String trendEmpty;

  /// The trend's window (µs), its legend toggles and `Reset zoom`.
  final RangeChanged<int> onTrendWindow;
  final ValueChanged<String>? onTrendToggle;
  final VoidCallback? onTrendReset;
  final String pointsLabel;
  final List<ColumnVm> columns;
  final List<RowVm> points;
  final String? pointsEmpty;

  /// How to pick points for the trend, under the points label.
  final String? pointsHint;

  /// A point row was clicked (its id); `add` when ⌘ or Ctrl was held: the
  /// point joins the trend instead of replacing what it shows.
  final ItemChanged<String, bool> onPoint;

  /// The historian's size, under the groups.
  final String? footer;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onAction;

  /// The groups and inspector widths the viewer chose.
  final SidePanelWidths panels;
  final ItemChanged<PanelSide, double>? onPanelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final left = Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s14,
              AppSpacing.s6,
              AppSpacing.s6,
            ),
            child: Row(
              children: [
                Expanded(child: SectionLabel(groupsLabel)),
                Tooltip(
                  message: addReason ?? '',
                  child: IconButton(
                    onPressed: addReason == null ? onAddGroup : null,
                    icon: Icon(Icons.add, size: 18, color: c.text3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              children: [
                for (final g in groups)
                  InkWell(
                    onTap: () => onGroup(g.id),
                    borderRadius: Radii.control,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.s10),
                      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: g.selected ? c.emberTint : null,
                        borderRadius: Radii.control,
                      ),
                      child: Column(
                        crossAxisAlignment: .start,
                        spacing: 2,
                        children: [
                          Text(
                            g.title,
                            style: TextStyle(
                              fontSize: FontSizes.body,
                              fontWeight: g.selected ? .w600 : .w400,
                              color: c.text1,
                            ),
                          ),
                          Text(
                            g.sub,
                            style: TextStyle(
                              fontSize: FontSizes.meta,
                              color: c.text4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (footer case final f?)
            Container(
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                f,
                style: TextStyle(
                  fontSize: FontSizes.meta,
                  height: 1.5,
                  color: c.text3,
                ),
              ),
            ),
        ],
      ),
    );
    final center = title == null
        ? Center(
            child: Text(empty, style: TextStyle(color: c.text4)),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s28,
              AppSpacing.lg,
              AppSpacing.s28,
              AppSpacing.s40,
            ),
            children: [
              Row(
                crossAxisAlignment: .start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 4,
                      children: [
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (subtitle case final s?)
                          Text(
                            s,
                            style: TextStyle(
                              fontSize: FontSizes.body,
                              color: c.text3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: SegmentedTabs(
                      tabs: ranges,
                      selected: range,
                      onSelect: onRange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s18),
              if (trend case final t?)
                Trend(
                  vm: t,
                  onWindow: onTrendWindow,
                  onSeriesToggle: onTrendToggle,
                  onReset: onTrendReset,
                )
              else
                Container(
                  height: 200,
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: c.ground1,
                    border: .all(color: c.line1),
                    borderRadius: Radii.card,
                  ),
                  child: Text(
                    trendEmpty,
                    style: TextStyle(fontSize: FontSizes.row, color: c.text4),
                  ),
                ),
              const SizedBox(height: AppSpacing.s22),
              SectionLabel(pointsLabel),
              if (pointsHint case final hint?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hint,
                  style: TextStyle(fontSize: FontSizes.meta, color: c.text4),
                ),
              ],
              const SizedBox(height: AppSpacing.s10),
              RowTable(
                columns: columns,
                rows: points,
                onTap: (id) {
                  final keys = HardwareKeyboard.instance;
                  onPoint(id, keys.isMetaPressed || keys.isControlPressed);
                },
                empty: pointsEmpty,
                rowHeight: 40,
              ),
            ],
          );
    return LayoutBuilder(
      builder: (context, box) => SidePanels(
        left: SidePanel(width: panels.left, defaultWidth: 240, child: left),
        center: center,
        right: inspector != null && box.maxWidth >= 1100
            ? SidePanel(
                width: panels.right,
                defaultWidth: 340,
                child: DetailInspector(vm: inspector!, onAction: onAction),
              )
            : null,
        onChanged: onPanelWidth,
      ),
    );
  }
}
