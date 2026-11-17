import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/quality_mark.dart';
import '../indicators/tag_chip.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// One cell: a title, a grey line under it, or a chip, or a state mark.
final class CellVm extends Equatable {
  const CellVm({
    this.title = '',
    this.subtitle,
    this.chip,
    this.tone,
    this.mark = Mark.dot,
    this.strong = false,
    this.monospace = false,
  });

  final String title;
  final String? subtitle;

  /// Drawn as a [TagChip] instead of the title.
  final String? chip;

  /// Drawn as a state word with its mark (the title in the tone's colour).
  final Tone? tone;
  final Mark mark;

  /// The first column: 600 weight.
  final bool strong;
  final bool monospace;

  @override
  List<Object?> get props => [
    title,
    subtitle,
    chip,
    tone,
    mark,
    strong,
    monospace,
  ];
}

/// One row of a [RowTable].
final class RowVm<T> extends Equatable {
  const RowVm({required this.cells, this.id, this.selected = false});

  /// What a tap on the row reports (an enum of a closed set, a thing's own
  /// name); null: the row is not one a tap reports (a history row, an
  /// audit record).
  final T? id;
  final List<CellVm> cells;
  final bool selected;

  @override
  List<Object?> get props => [id, cells, selected];
}

/// A column: its header and its share of the width.
final class ColumnVm extends Equatable {
  const ColumnVm(this.label, {this.flex = 1});

  final String label;
  final int flex;

  @override
  List<Object?> get props => [label, flex];
}

/// Board *Studio · Links* table: a card (radius 10) with a header row and
/// 58 px rows; the selected row has an ember bar on the left on the ember
/// fill.
class RowTable<T> extends StatelessWidget {
  /// [onTap] gets the id of the row tapped; null leaves the rows inert.
  RowTable({
    required this.columns,
    required this.rows,
    ValueChanged<T>? onTap,
    this.empty,
    this.rowHeight = 58,
    super.key,
  }) : _onTap = onTap == null
           ? null
           : [
               for (final r in rows)
                 switch (r.id) {
                   final id? => () => onTap(id),
                   null => null,
                 },
             ];

  /// 58 for two-line rows, 40 for one line (points, history).
  final double rowHeight;

  final List<ColumnVm> columns;
  final List<RowVm<T>> rows;

  // The callback is applied to each id here, in the constructor: a field
  // of type `ValueChanged<T>` would hold `T` against its variance.
  final List<VoidCallback?>? _onTap;

  /// Shown as the only row when there are none.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                for (final col in columns)
                  Expanded(
                    flex: col.flex,
                    child: Text(
                      col.label,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(
                        fontSize: FontSizes.sm,
                        color: c.text3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (rows.isEmpty && empty != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line1)),
              ),
              child: Text(
                empty!,
                style: TextStyle(fontSize: FontSizes.md, color: c.text4),
              ),
            ),
          for (final (i, r) in rows.indexed)
            InkWell(
              onTap: _onTap?[i],
              hoverColor: c.ground3,
              child: Container(
                constraints: BoxConstraints(minHeight: rowHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: r.selected ? c.emberFill : null,
                  border: Border(
                    top: BorderSide(color: c.line1),
                    left: BorderSide(
                      color: r.selected ? c.ember : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      Expanded(
                        flex: columns[i].flex,
                        child: i < r.cells.length
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.sm,
                                ),
                                child: _Cell(vm: r.cells[i]),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.vm});

  final CellVm vm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget head;
    if (vm.chip case final chip?) {
      head = Align(
        alignment: .centerLeft,
        child: TagChip(vm: TagChipVm(label: chip)),
      );
    } else if (vm.tone case final t?) {
      head = QualityMark(
        vm: QualityMarkVm(label: vm.title, tone: t, mark: vm.mark),
      );
    } else {
      final base = TextStyle(
        fontSize: vm.strong ? FontSizes.lg : FontSizes.md,
        fontWeight: vm.strong ? .w600 : .w400,
        color: vm.strong ? c.text1 : c.text2,
      );
      head = Text(
        vm.title,
        maxLines: 1,
        overflow: .ellipsis,
        style: vm.monospace ? mono(color: base.color) : base,
      );
    }
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      spacing: 2,
      children: [
        head,
        if (vm.subtitle case final s?)
          Text(
            s,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
          ),
      ],
    );
  }
}
