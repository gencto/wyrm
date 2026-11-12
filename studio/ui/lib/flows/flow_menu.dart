import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../theme/extensions/colors.dart';
import '../theme/typography.dart';
import 'shortcut_card.dart';

/// One command of a [FlowMenu].
final class FlowMenuItemVm extends Equatable {
  const FlowMenuItemVm(
    this.command, {
    this.disabledReason,
    this.danger = false,
    this.divider = false,
  });

  final FlowCommand command;

  /// Why it cannot be picked (its tooltip); null: it can.
  final String? disabledReason;
  final bool danger;

  /// A line above it.
  final bool divider;

  @override
  List<Object?> get props => [command, disabledReason, danger, divider];
}

/// One field of the block in the `Fields ▸` checklist.
final class FlowPinVm extends Equatable {
  const FlowPinVm({
    required this.id,
    required this.label,
    required this.pinned,
    this.lockedReason,
  });

  /// The field's id within its block.
  final String id;
  final String label;

  /// Whether it is a row of the block now.
  final bool pinned;

  /// Why it cannot be taken off (`bound`); null: it can.
  final String? lockedReason;

  @override
  List<Object?> get props => [id, label, pinned, lockedReason];
}

/// What a [FlowMenu] shows: the block, the selection or the canvas it was
/// opened on, its commands, and the fields of the block when it is one.
final class FlowMenuVm extends Equatable {
  const FlowMenuVm({
    required this.title,
    required this.items,
    this.subtitle = '',
    this.fields = const [],
    this.unpin,
  });

  /// The block's id, `3 blocks`, or the flow.
  final String title;

  /// The block's type, or how many blocks the flow has.
  final String subtitle;
  final List<FlowMenuItemVm> items;

  /// The checklist behind [FlowCommand.fields].
  final List<FlowPinVm> fields;

  /// The row the menu was opened on: [FlowCommand.unpin] takes it off the
  /// block (disabled with its `lockedReason` when it is bound).
  final FlowPinVm? unpin;

  @override
  List<Object?> get props => [title, subtitle, items, fields, unpin];
}

/// The context menu of the flow canvas (spec §13), in the style of the
/// node menu: the name of what it was opened on over its commands, each
/// with its shortcut on the right ([flowHintOf]). `Fields ▸`
/// opens a checklist beside it: a tick pins a field to the block or takes
/// it off, and the menu stays open. [onPick] gets a command, [onPin] a
/// field and whether it is pinned now.
class FlowMenu extends StatefulWidget {
  const FlowMenu({
    required this.vm,
    required this.onPick,
    required this.onPin,
    this.fieldsOpen = false,
    this.mac,
    super.key,
  });

  final FlowMenuVm vm;
  final ValueChanged<FlowCommand> onPick;
  final void Function(String field, {required bool pinned}) onPin;

  /// Whether the `Fields ▸` checklist is open at first.
  final bool fieldsOpen;

  /// ⌘ glyphs or `Ctrl+`; null: this machine's.
  final bool? mac;

  static const width = 260.0;

  /// Shows the menu at [at] (global) and returns the command picked.
  static Future<FlowCommand?> show(
    BuildContext context, {
    required Offset at,
    required FlowMenuVm vm,
    required void Function(String field, {required bool pinned}) onPin,
  }) => showDialog<FlowCommand>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      // Room for the checklist on the right; else the menu moves left.
      final room = vm.fields.isEmpty ? width : width * 2;
      return Stack(
        children: [
          Positioned(
            left: at.dx.clamp(8, (size.width - room - 8).clamp(8, size.width)),
            top: at.dy.clamp(8, (size.height - 380).clamp(8, size.height)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height - 16),
              child: FlowMenu(
                vm: vm,
                onPin: onPin,
                onPick: (c) => Navigator.of(context).pop(c),
              ),
            ),
          ),
        ],
      );
    },
  );

  @override
  State<FlowMenu> createState() => _FlowMenuState();
}

class _FlowMenuState extends State<FlowMenu> {
  late bool _fields = widget.fieldsOpen;

  /// The ticks as the user set them while the menu is open.
  late final Map<String, bool> _pinned = {
    for (final f in widget.vm.fields) f.id: f.pinned,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;

    Widget panel(List<Widget> children) => Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: FlowMenu.width,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: children,
          ),
        ),
      ),
    );

    Widget item(FlowMenuItemVm i) {
      final isFields = i.command == FlowCommand.fields;
      final unpin = i.command == FlowCommand.unpin ? vm.unpin : null;
      final reason = i.disabledReason ?? unpin?.lockedReason;
      final enabled = reason == null;
      final hint = flowHintOf(i.command, mac: widget.mac);
      final row = InkWell(
        onTap: !enabled
            ? null
            : (isFields
                  ? () => setState(() => _fields = !_fields)
                  : () => widget.onPick(i.command)),
        onHover: isFields || !_fields
            ? null
            : (over) {
                if (over) {
                  setState(() => _fields = false);
                }
              },
        child: Container(
          height: 34,
          color: isFields && _fields ? c.ground4 : null,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  unpin == null
                      ? flowCommandLabel(i.command)
                      : S.current.fmUnpinField(unpin.label),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: !enabled
                        ? c.muted
                        : (i.danger ? c.badText : c.text1),
                  ),
                ),
              ),
              if (isFields)
                AppIcon('ui_chevron_right', size: 14, color: c.text3)
              else if (hint.isNotEmpty)
                Row(
                  mainAxisSize: .min,
                  spacing: 1,
                  children: [
                    for (final t in KeyGlyph.tokens(hint))
                      KeyGlyph(t, color: c.text4, size: 12),
                  ],
                ),
            ],
          ),
        ),
      );
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          if (i.divider) Divider(height: 9, color: c.line1),
          if (enabled) row else Tooltip(message: reason, child: row),
        ],
      );
    }

    Widget field(FlowPinVm f) {
      final on = _pinned[f.id] ?? f.pinned;
      final locked = f.lockedReason != null;
      final row = InkWell(
        onTap: locked
            ? null
            : () {
                setState(() => _pinned[f.id] = !on);
                widget.onPin(f.id, pinned: !on);
              },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: .center,
                decoration: BoxDecoration(
                  color: on ? (locked ? c.ground4 : c.emberTint) : null,
                  border: .all(color: on && !locked ? c.ember : c.line3),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
                child: on
                    ? AppIcon(
                        'ui_check',
                        size: 12,
                        color: locked ? c.text4 : c.emberSoft,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  f.label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: locked ? c.text3 : c.text1,
                  ),
                ),
              ),
              if (f.lockedReason case final why?)
                Text(why, style: TextStyle(fontSize: 11, color: c.text4)),
            ],
          ),
        ),
      );
      return row;
    }

    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        panel([
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Row(
              spacing: 8,
              children: [
                Flexible(
                  flex: 3,
                  child: Text(
                    vm.title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: mono(weight: .w600, color: c.text1),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Text(
                    vm.subtitle,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 12, color: c.text4),
                  ),
                ),
              ],
            ),
          ),
          for (final i in vm.items) item(i),
        ]),
        if (_fields && vm.fields.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: panel([
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Text(
                  S.current.fmFieldsTitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: .w600,
                    letterSpacing: 0.66,
                    color: c.text4,
                  ),
                ),
              ),
              for (final f in vm.fields) field(f),
            ]),
          ),
      ],
    );
  }
}
