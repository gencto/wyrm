import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../containers/section_label.dart';
import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';
import 'tree_row.dart';

/// The footer of the tree: a sentence with a code span and links to other
/// workspaces (`The tree shows data only. sys/** is edited in Links, …`).
final class TreeNoteVm extends Equatable {
  const TreeNoteVm({
    required this.lead,
    required this.code,
    required this.middle,
    required this.links,
    required this.and,
  });

  /// `The tree shows data only.`
  final String lead;

  /// `sys/**`.
  final String code;

  /// `is edited in`.
  final String middle;

  /// `(id, label)` of each workspace named, in order.
  final List<(String, String)> links;

  /// `and` before the last link.
  final String and;

  @override
  List<Object?> get props => [lead, code, middle, links, and];
}

/// The tree panel of Explorer (flex 260–300, docs/design/specs/explorer.md
/// §2): a label, the Filter field, the rows, a note at the bottom. Rows come
/// in display order, already indented and filtered.
///
/// A tap selects a row ([onTap]); ⌘/Ctrl-click ([onMark]) and Shift-click
/// ([onMarkRange]) add rows to a selection for Copy keys. [loading] draws
/// skeleton rows.
class NodeTree extends StatelessWidget {
  const NodeTree({
    required this.label,
    required this.rows,
    required this.onTap,
    required this.onToggle,
    this.onMenu,
    this.onMark,
    this.onMarkRange,
    this.filter,
    this.onFilter,
    this.filterHint = '',
    this.note,
    this.onNoteLink,
    this.loading = false,
    this.width = 290,
    super.key,
  });

  final String label;
  final List<TreeRowVm> rows;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onToggle;

  /// A right click, a long press or the `⋯` of the selected row: its actions.
  final void Function(String id, Offset at)? onMenu;
  final ValueChanged<String>? onMark;
  final ValueChanged<String>? onMarkRange;
  final String? filter;
  final ValueChanged<String>? onFilter;
  final String filterHint;
  final TreeNoteVm? note;

  /// A workspace link of the note, by its id.
  final ValueChanged<String>? onNoteLink;
  final bool loading;
  final double width;

  void _tap(String id) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed && onMarkRange != null) {
      onMarkRange!(id);
    } else if ((keys.isMetaPressed || keys.isControlPressed) &&
        onMark != null) {
      onMark!(id);
    } else {
      onTap(id);
    }
  }

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
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 10,
              children: [
                SectionLabel(label),
                if (onFilter != null) _filter(c),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (var i = 0; i < 8; i++) _skeleton(c, i),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: GestureDetector(
                        onSecondaryTapUp: onMenu == null
                            ? null
                            : (d) => onMenu!(rows[i].id, d.globalPosition),
                        onLongPressStart: onMenu == null
                            ? null
                            : (d) => onMenu!(rows[i].id, d.globalPosition),
                        child: TreeRow(
                          vm: rows[i],
                          onTap: _tap,
                          onToggle: onToggle,
                          onMore: onMenu,
                        ),
                      ),
                    ),
                  ),
          ),
          if (note case final n?)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: _note(c, n),
            ),
        ],
      ),
    );
  }

  Widget _filter(AppColors c) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: c.ground3,
      border: .all(color: c.line1),
      borderRadius: Radii.segment,
    ),
    child: Row(
      spacing: 8,
      children: [
        AppIcon('ui_filter', size: 14, color: c.text4),
        Expanded(
          child: TextFormField(
            initialValue: filter,
            onChanged: onFilter,
            style: TextStyle(fontSize: 13, color: c.text1),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: filterHint,
              hintStyle: TextStyle(fontSize: 13, color: c.text4),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _skeleton(AppColors c, int i) => Container(
    height: 40,
    padding: EdgeInsets.only(left: 10.0 + (i % 3) * 16, right: 10),
    alignment: .centerLeft,
    child: Container(
      width: 90.0 + (i * 37) % 80,
      height: 10,
      decoration: BoxDecoration(color: c.ground3, borderRadius: Radii.chip),
    ),
  );

  Widget _note(AppColors c, TreeNoteVm n) {
    final base = TextStyle(fontSize: 12, height: 1.5, color: c.text4);
    final link = TextStyle(
      color: c.text2,
      decoration: TextDecoration.underline,
      decorationColor: c.text2,
    );
    Widget a((String, String) l) => GestureDetector(
      onTap: onNoteLink == null ? null : () => onNoteLink!(l.$1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(l.$2, style: base.merge(link)),
      ),
    );
    final spans = <InlineSpan>[
      TextSpan(text: '${n.lead} '),
      TextSpan(
        text: n.code,
        style: mono(size: 12, color: c.text3),
      ),
      TextSpan(text: ' ${n.middle} '),
      for (final (i, l) in n.links.indexed) ...[
        if (i > 0 && i == n.links.length - 1)
          TextSpan(text: ' ${n.and} ')
        else if (i > 0)
          const TextSpan(text: ', '),
        WidgetSpan(alignment: .baseline, baseline: .alphabetic, child: a(l)),
      ],
      const TextSpan(text: '.'),
    ];
    return Text.rich(TextSpan(children: spans), style: base);
  }
}
