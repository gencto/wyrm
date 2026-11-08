import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../indicators/quality_mark.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/typography.dart';

/// One point of a device as its row shows it; every text already formatted.
final class PointRowVm extends Equatable {
  const PointRowVm({
    required this.id,
    required this.name,
    required this.quality,
    this.display,
    this.register = '—',
    this.type = '—',
    this.unit = '—',
    this.poll = '—',
    this.pollWas,
    this.value = '—',
    this.writable = false,
    this.checked = false,
    this.selected = false,
    this.staged = false,
    this.stale = false,
  });

  /// The point's key.
  final String id;
  final String name;
  final String? display;

  /// `HR 10`, `Coil 1`.
  final String register;
  final String type;
  final String unit;

  /// `1 s`; the staged rate when [pollWas] is set.
  final String poll;

  /// The rate before the staged edit (`was 1 s` under it, ember above).
  final String? pollWas;

  /// The value without its unit.
  final String value;
  final QualityMarkVm quality;
  final bool writable;
  final bool checked;
  final bool selected;

  /// A change to this point waits for Review and apply.
  final bool staged;

  /// Offline: the value is greyed.
  final bool stale;

  @override
  List<Object?> get props => [
    id,
    name,
    display,
    register,
    type,
    unit,
    poll,
    pollWas,
    value,
    quality,
    writable,
    checked,
    selected,
    staged,
    stale,
  ];
}

/// The headers of a [PointsTable], localized by the connector.
final class PointsTableLabels {
  const PointsTableLabels({
    this.point = 'Point',
    this.register = 'Register',
    this.type = 'Type',
    this.unit = 'Unit',
    this.poll = 'Poll',
    this.value = 'Value',
    this.quality = 'Quality',
    this.write = 'Write',
    this.was = 'was',
  });

  final String point;
  final String register;
  final String type;
  final String unit;
  final String poll;
  final String value;
  final String quality;
  final String write;

  /// `was` in `was 1 s`.
  final String was;
}

/// The points of a device (docs/design/specs/explorer.md §3.5): a card of
/// select, Point, Register, Type, Unit, Poll, Value, Quality and Write,
/// header 40, rows 40 (32 compact); a selected row on ground/3, a staged
/// one on the ember fill with a dot by its name. Narrower than 720 it
/// scrolls sideways (the board shows every column at 1440, where the
/// workspace is 784 wide). [loading] draws six skeleton rows.
///
/// A click selects the row ([onTap]); the checkbox or ⌘/Ctrl-click toggles
/// it ([onCheck]); Shift-click checks the range ([onRange]); the header box
/// checks every row ([onCheckAll]).
class PointsTable extends StatelessWidget {
  const PointsTable({
    required this.rows,
    this.labels = const PointsTableLabels(),
    this.onTap,
    this.onCheck,
    this.onRange,
    this.onCheckAll,
    this.loading = false,
    this.rowHeight = 40,
    super.key,
  });

  final List<PointRowVm> rows;
  final PointsTableLabels labels;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onCheck;
  final ValueChanged<String>? onRange;
  final VoidCallback? onCheckAll;
  final bool loading;
  final double rowHeight;

  static const _flex = [15, 11, 9, 6, 9, 9, 10, 5];
  static const minWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = rows.isNotEmpty && rows.every((r) => r.checked);
    final some = rows.any((r) => r.checked);
    return Container(
      decoration: BoxDecoration(
        color: c.ground1,
        border: .all(color: c.line1),
        borderRadius: Radii.card,
      ),
      clipBehavior: .antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth < minWidth ? minWidth : box.maxWidth;
          final table = SizedBox(
            width: w,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                _header(c, all: all, some: some),
                if (loading)
                  for (var i = 0; i < 6; i++) _skeleton(c)
                else
                  for (final r in rows) _row(context, c, r),
              ],
            ),
          );
          return box.maxWidth < minWidth
              ? SingleChildScrollView(
                  scrollDirection: .horizontal,
                  child: table,
                )
              : table;
        },
      ),
    );
  }

  Widget _cells(List<Widget> cells) => Row(
    children: [
      for (final (i, cell) in cells.indexed)
        if (i == 0)
          SizedBox(width: 44, child: Center(child: cell))
        else
          Expanded(flex: _flex[i - 1], child: cell),
    ],
  );

  Widget _header(AppColors c, {required bool all, required bool some}) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: .w600,
      letterSpacing: 0.48,
      color: c.text4,
    );
    Text h(String s) => Text(s.toUpperCase(), style: style);
    return Container(
      height: 40,
      padding: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line1)),
      ),
      child: _cells([
        _Box(
          value: all ? true : (some ? null : false),
          onTap: onCheckAll,
        ),
        h(labels.point),
        h(labels.register),
        h(labels.type),
        h(labels.unit),
        h(labels.poll),
        h(labels.value),
        h(labels.quality),
        h(labels.write),
      ]),
    );
  }

  Widget _skeleton(AppColors c) => Container(
    height: rowHeight,
    padding: const EdgeInsets.only(right: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: c.ground3)),
    ),
    child: _cells([
      const SizedBox.shrink(),
      for (var i = 0; i < 8; i++)
        Align(
          alignment: .centerLeft,
          child: FractionallySizedBox(
            widthFactor: i == 0 ? 0.6 : 0.4,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: c.ground3,
                borderRadius: Radii.chip,
              ),
            ),
          ),
        ),
    ]),
  );

  Widget _row(BuildContext context, AppColors c, PointRowVm r) {
    final valueColor = r.stale ? c.muted : c.text1;
    return Material(
      color: r.selected ? c.ground3 : (r.staged ? c.emberFill : c.ground1),
      child: InkWell(
        onTap: () {
          final keys = HardwareKeyboard.instance;
          if (keys.isShiftPressed && onRange != null) {
            onRange!(r.id);
          } else if ((keys.isMetaPressed || keys.isControlPressed) &&
              onCheck != null) {
            onCheck!(r.id);
          } else {
            onTap?.call(r.id);
          }
        },
        hoverColor: c.ground2,
        child: Container(
          constraints: BoxConstraints(minHeight: rowHeight),
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.ground3)),
          ),
          child: _cells([
            _Box(
              value: r.checked,
              onTap: onCheck == null ? null : () => onCheck!(r.id),
            ),
            Row(
              spacing: 8,
              children: [
                if (r.staged)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: .circle, color: c.ember),
                  ),
                // One line: the name, then the display name in what is
                // left, the ellipsis at its end (a long name cuts it too).
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text.rich(
                      TextSpan(
                        text: r.name,
                        style: mono(color: c.text1),
                        children: [
                          if (r.display case final d?)
                            TextSpan(
                              text: '  $d',
                              style: TextStyle(
                                fontFamily: AppFonts.sans,
                                fontSize: 13,
                                color: c.text4,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              r.register,
              maxLines: 1,
              overflow: .ellipsis,
              style: mono(color: c.text2),
            ),
            Text(
              r.type,
              maxLines: 1,
              overflow: .ellipsis,
              style: mono(color: c.text3),
            ),
            Text(
              r.unit,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(fontSize: 14, color: c.text2),
            ),
            Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  r.poll,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: r.pollWas == null ? .w400 : .w600,
                    color: r.pollWas == null ? c.text2 : c.emberSoft,
                  ),
                ),
                if (r.pollWas case final w?)
                  Text(
                    '${labels.was} $w',
                    style: TextStyle(fontSize: 12, color: c.text4),
                  ),
              ],
            ),
            Text(
              r.value,
              overflow: .ellipsis,
              maxLines: 1,
              style: mono(color: valueColor),
            ),
            QualityMark(vm: r.quality),
            Text(
              r.writable ? 'RW' : 'R',
              style: TextStyle(
                fontSize: 13,
                color: r.writable ? c.text1 : c.text4,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The 16 px checkbox of a row, ember when checked; null is "some".
class _Box extends StatelessWidget {
  const _Box({required this.value, this.onTap});

  final bool? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = value ?? true;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.chip,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: on ? c.ember : c.ground3,
          border: .all(color: on ? c.ember : c.line3),
          borderRadius: const BorderRadius.all(Radius.circular(3)),
        ),
        child: switch (value) {
          true => Icon(Icons.check, size: 12, color: c.onEmber),
          null => Icon(Icons.remove, size: 12, color: c.onEmber),
          false => null,
        },
      ),
    );
  }
}
