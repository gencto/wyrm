import 'package:flutter/material.dart';

import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import 'tree_row.dart';

/// The tree panel of Explorer (260–300): a label, a filter, the rows, a
/// note at the bottom. Rows come in display order, already indented.
class NodeTree extends StatelessWidget {
  const NodeTree({
    required this.label,
    required this.rows,
    required this.onTap,
    required this.onToggle,
    this.onMenu,
    this.filter,
    this.onFilter,
    this.filterHint = '',
    this.note,
    this.width = 290,
    super.key,
  });

  final String label;
  final List<TreeRowVm> rows;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onToggle;

  /// A right click or a long press on a row: its actions.
  final void Function(String id, Offset at)? onMenu;
  final String? filter;
  final ValueChanged<String>? onFilter;
  final String filterHint;
  final String? note;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.ground1,
        border: Border(right: BorderSide(color: c.line1)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 10,
              children: [
                SectionLabel(label),
                if (onFilter != null)
                  SizedBox(
                    height: 36,
                    child: TextFormField(
                      initialValue: filter,
                      onChanged: onFilter,
                      style: TextStyle(fontSize: 13, color: c.text1),
                      decoration: InputDecoration(
                        hintText: filterHint,
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(10),
                          child: AppIcon('ui_search', size: 16, color: c.text4),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: rows.length,
              itemBuilder: (_, i) => GestureDetector(
                onSecondaryTapUp: onMenu == null
                    ? null
                    : (d) => onMenu!(rows[i].id, d.globalPosition),
                onLongPressStart: onMenu == null
                    ? null
                    : (d) => onMenu!(rows[i].id, d.globalPosition),
                child: TreeRow(vm: rows[i], onTap: onTap, onToggle: onToggle),
              ),
            ),
          ),
          if (note case final n?)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                n,
                style: TextStyle(fontSize: 12, height: 1.5, color: c.text3),
              ),
            ),
        ],
      ),
    );
  }
}
