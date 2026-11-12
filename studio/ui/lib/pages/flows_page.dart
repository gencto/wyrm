import 'package:material_ui/material_ui.dart';

import '../buttons/button.dart';
import '../containers/detail_inspector.dart';
import '../containers/page_header.dart';
import '../tables/row_table.dart';

/// Board *Studio · Flows*: the site's flows with their state, what they
/// read and write, and the inspector of the selected one with Edit.
class FlowsPage extends StatelessWidget {
  const FlowsPage({
    required this.title,
    required this.subtitle,
    required this.newLabel,
    required this.columns,
    required this.rows,
    required this.onRow,
    required this.onAction,
    this.onTapFlowEditor,
    this.newReason,
    this.empty,
    this.inspector,
    super.key,
  });

  final String title;
  final String subtitle;
  final String newLabel;
  final String? newReason;

  /// Opens the editor on a new flow.
  final VoidCallback? onTapFlowEditor;
  final List<ColumnVm> columns;
  final List<RowVm> rows;
  final String? empty;
  final ValueChanged<String> onRow;
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
          trailing: Button.primary(
            label: newLabel,
            icon: 'ui_add',
            disabledReason: newReason,
            onPressed: newReason == null ? onTapFlowEditor : null,
          ),
        ),
        const SizedBox(height: 20),
        RowTable(columns: columns, rows: rows, onTap: onRow, empty: empty),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final ins = inspector;
        if (ins == null || box.maxWidth < 1000) {
          return body;
        }
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(child: body),
            DetailInspector(vm: ins, onAction: onAction),
          ],
        );
      },
    );
  }
}
