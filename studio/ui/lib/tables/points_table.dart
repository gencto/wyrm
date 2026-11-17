import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../indicators/app_icon_view.dart';
import '../indicators/fail_chip.dart';
import '../indicators/quality_mark.dart';
import '../indicators/sample_mark.dart';
import '../indicators/value_type.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// A modbus register area, as the table abbreviates it.
enum RegisterArea {
  holding,
  input,
  coil,
  discrete;

  String get label => switch (this) {
    holding => S.current.areaHolding,
    input => S.current.areaInput,
    coil => S.current.areaCoil,
    discrete => S.current.areaDiscrete,
  };
}

/// Where a point is read on its device.
sealed class RegisterVm extends Equatable {
  const RegisterVm();

  /// `HR 10`, `Coil 1`, `DB1.DBX0.0`, `—`.
  String get text;
}

/// A modbus area ([area] when known, else the driver's [table] name) and
/// the offset [addr].
final class ModbusRegisterVm extends RegisterVm {
  const ModbusRegisterVm({required this.addr, this.area, this.table});

  final String addr;
  final RegisterArea? area;
  final String? table;

  @override
  String get text => switch (area?.label ?? table) {
    final a? when a.isNotEmpty => '$a $addr',
    _ => addr,
  };

  @override
  List<Object?> get props => [addr, area, table];
}

/// A driver's own address (`cfg.address`).
final class AddressRegisterVm extends RegisterVm {
  const AddressRegisterVm(this.address);

  final String address;

  @override
  String get text => address;

  @override
  List<Object?> get props => [address];
}

/// No register known.
final class NoRegisterVm extends RegisterVm {
  const NoRegisterVm();

  @override
  String get text => '—';

  @override
  List<Object?> get props => [];
}

/// One point of a device as its row shows it: typed values, worded here.
final class PointRowVm extends Equatable {
  const PointRowVm({
    required this.id,
    required this.mark,
    this.name,
    this.display,
    this.register = const NoRegisterVm(),
    this.dtype,
    this.type,
    this.unit,
    this.poll,
    this.pollWas,
    this.value,
    this.writable = false,
    this.checked = false,
    this.selected = false,
    this.staged = false,
    this.stale = false,
    this.failed,
  });

  /// The point's key.
  final String id;

  /// Null: a point staged with no name yet (`—`).
  final String? name;
  final String? display;
  final RegisterVm register;

  /// The driver's data type (`f32_wswap`), shown before the value's type.
  final String? dtype;
  final ValueType? type;
  final String? unit;

  /// The poll rate in seconds; the staged one when [pollWas] is set.
  final num? poll;

  /// The rate before the staged edit (`was 1 s` under it, ember above).
  final num? pollWas;

  /// The value as the user reads it, without its unit; null: `—`.
  final String? value;
  final SampleMark mark;
  final bool writable;
  final bool checked;
  final bool selected;

  /// A change to this point waits for Review and apply.
  final bool staged;

  /// Offline: the value is greyed.
  final bool stale;

  /// Reading its value failed, and why: the chip beside the name
  /// (`read failed`, docs/design/specs/errors.md §4); the value is `—`.
  final String? failed;

  @override
  List<Object?> get props => [
    id,
    name,
    display,
    register,
    dtype,
    type,
    unit,
    poll,
    pollWas,
    value,
    mark,
    writable,
    checked,
    selected,
    staged,
    stale,
    failed,
  ];
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
    this.onTap,
    this.onCheck,
    this.onRange,
    this.onCheckAll,
    this.loading = false,
    this.rowHeight = 40,
    super.key,
  });

  final List<PointRowVm> rows;
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
      fontSize: FontSizes.sm,
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
        h(S.current.colPoint),
        h(S.current.colRegister),
        h(S.current.colType),
        h(S.current.colUnit),
        h(S.current.colPoll),
        h(S.current.colValue),
        h(S.current.colQuality),
        h(S.current.colWrite),
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
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Text.rich(
                      TextSpan(
                        text: r.name ?? '—',
                        style: mono(color: c.text1),
                        children: [
                          if (r.display case final d?)
                            TextSpan(
                              text: '  $d',
                              style: TextStyle(
                                fontFamily: AppFonts.sans,
                                fontSize: FontSizes.md,
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
                if (r.failed case final f?)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: FailChip(
                      vm: FailChipVm.reads([ReadFailed(.value, f)]),
                    ),
                  ),
              ],
            ),
            Text(
              r.register.text,
              maxLines: 1,
              overflow: .ellipsis,
              style: mono(color: c.text2),
            ),
            Text(
              r.dtype ?? r.type?.word ?? '—',
              maxLines: 1,
              overflow: .ellipsis,
              style: mono(color: c.text3),
            ),
            Text(
              r.unit ?? '—',
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(fontSize: FontSizes.lg, color: c.text2),
            ),
            Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  switch (r.poll) {
                    final p? => Formats.pollRate(p),
                    null => '—',
                  },
                  style: TextStyle(
                    fontSize: FontSizes.lg,
                    fontWeight: r.pollWas == null ? .w400 : .w600,
                    color: r.pollWas == null ? c.text2 : c.emberSoft,
                  ),
                ),
                if (r.pollWas case final w?)
                  Text(
                    '${S.current.wasWord} ${Formats.pollRate(w)}',
                    style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
                  ),
              ],
            ),
            Text(
              r.value ?? '—',
              overflow: .ellipsis,
              maxLines: 1,
              style: mono(color: valueColor),
            ),
            QualityMark(vm: r.mark.vm()),
            Text(
              r.writable ? S.current.pointRw : S.current.pointR,
              style: TextStyle(
                fontSize: FontSizes.md,
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
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mark)),
        ),
        child: switch (value) {
          true => AppIconView(
            AppIcon.materialCheck,
            size: IconSizes.xs,
            color: c.onEmber,
          ),
          null => AppIconView(
            AppIcon.materialMixed,
            size: IconSizes.xs,
            color: c.onEmber,
          ),
          false => null,
        },
      ),
    );
  }
}
