import 'package:flutter/material.dart';

import '../buttons/button.dart';
import '../buttons/segmented_tabs.dart';
import '../containers/detail_inspector.dart';
import '../containers/page_header.dart';
import '../overlays/log_view.dart';
import '../tables/row_table.dart';

/// Board *Studio · Access*: the gateway's users, the grants of roles and
/// subjects, the audit tail; the inspector of the selected user.
class AccessPage extends StatelessWidget {
  const AccessPage({
    required this.title,
    required this.subtitle,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.columns,
    required this.rows,
    required this.onRow,
    required this.onAction,
    required this.addLabel,
    required this.onAdd,
    this.addReason,
    this.empty,
    this.audit = const [],
    this.inspector,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<TabItemVm> tabs;
  final String tab;
  final ValueChanged<String> onTab;
  final List<ColumnVm> columns;
  final List<RowVm> rows;
  final ValueChanged<String> onRow;
  final String? empty;

  /// The audit tab's lines.
  final List<String> audit;
  final String addLabel;
  final VoidCallback onAdd;
  final String? addReason;
  final DetailInspectorVm? inspector;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
      children: [
        PageHeader(
          title: title,
          subtitle: subtitle,
          trailing: tab == 'audit'
              ? null
              : Button.primary(
                  label: addLabel,
                  icon: 'ui_add',
                  disabledReason: addReason,
                  onPressed: addReason == null ? onAdd : null,
                ),
        ),
        const SizedBox(height: 20),
        SegmentedTabs(tabs: tabs, selected: tab, onSelect: onTab),
        const SizedBox(height: 16),
        if (tab == 'audit')
          SizedBox(
            height: 560,
            child: LogView(lines: audit, empty: empty ?? ''),
          )
        else
          RowTable(
            columns: columns,
            rows: rows,
            onTap: onRow,
            empty: empty,
            rowHeight: 48,
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(child: body),
          if (inspector != null && box.maxWidth >= 1000)
            DetailInspector(vm: inspector!, onAction: onAction),
        ],
      ),
    );
  }
}
