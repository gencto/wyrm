import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../buttons/segmented_tabs.dart';
import '../charts/trend_chart.dart';
import '../containers/detail_inspector.dart';
import '../containers/section_label.dart';
import '../tables/row_table.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';

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
/// group's trend and points, its settings and actions.
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
    required this.trendLabels,
    required this.trendEmpty,
    required this.pointsLabel,
    required this.columns,
    required this.points,
    required this.onAction,
    this.addReason,
    this.title,
    this.subtitle,
    this.empty = '',
    this.pointsEmpty,
    this.footer,
    this.inspector,
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
  final List<TrendSeriesVm> trend;
  final (String, String) trendLabels;
  final String trendEmpty;
  final String pointsLabel;
  final List<ColumnVm> columns;
  final List<RowVm> points;
  final String? pointsEmpty;

  /// The historian's size, under the groups.
  final String? footer;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onAction;

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
            padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final g in groups)
                  InkWell(
                    onTap: () => onGroup(g.id),
                    borderRadius: Radii.control,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 4),
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
                              fontSize: 14,
                              fontWeight: g.selected ? .w600 : .w400,
                              color: c.text1,
                            ),
                          ),
                          Text(
                            g.sub,
                            style: TextStyle(fontSize: 12, color: c.text4),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                f,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.text3),
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
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
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
                            style: TextStyle(fontSize: 14, color: c.text3),
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
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: c.ground1,
                  border: .all(color: c.line1),
                  borderRadius: Radii.card,
                ),
                child: TrendChart(
                  series: trend,
                  empty: trendEmpty,
                  timeLabels: trendLabels,
                  height: 260,
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel(pointsLabel),
              const SizedBox(height: 10),
              RowTable(
                columns: columns,
                rows: points,
                onTap: onAction,
                empty: pointsEmpty,
                rowHeight: 40,
              ),
            ],
          );
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: .stretch,
        children: [
          left,
          Expanded(child: center),
          if (inspector != null && box.maxWidth >= 1100)
            DetailInspector(vm: inspector!, onAction: onAction),
        ],
      ),
    );
  }
}
