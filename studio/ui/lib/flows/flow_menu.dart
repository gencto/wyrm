import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../indicators/app_icon.dart';
import '../models/disabled.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/sizes.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'field_word.dart';
import 'shortcut_card.dart';

/// One command of a [FlowMenu].
final class FlowMenuItemVm extends Equatable {
  const FlowMenuItemVm(
    this.command, {
    this.off,
    this.danger = false,
    this.divider = false,
  });

  final FlowCommand command;

  /// Why it cannot be picked (its tooltip); null: it can.
  final Disabled? off;
  final bool danger;

  /// A line above it.
  final bool divider;

  @override
  List<Object?> get props => [command, off, danger, divider];
}

/// One field of the block in the `Fields ▸` checklist.
final class FlowPinVm extends Equatable {
  const FlowPinVm({
    required this.label,
    required this.pinned,
    this.word,
    this.locked = false,
    this.onPin,
  });

  /// The field's label when it is data; [word] when it is Studio's word.
  final String label;
  final FieldWordVm? word;

  /// What the item reads, in the language on screen.
  String get reads => word?.text ?? label;

  /// Whether it is a row of the block now.
  final bool pinned;

  /// Bound: it cannot be taken off (`bound`).
  final bool locked;

  /// Pins it to the block (true) or takes it off; null: it cannot change.
  final ValueChanged<bool>? onPin;

  /// Why it cannot be taken off; null: it can.
  String? get lockedReason => locked ? S.current.fmBound : null;

  @override
  List<Object?> get props => [label, word, pinned, locked, onPin != null];
}

/// What a [FlowMenu] shows: the block, the selection or the canvas it was
/// opened on, its commands, and the fields of the block when it is one.
final class FlowMenuVm extends Equatable {
  const FlowMenuVm({
    required this.items,
    this.block,
    this.blockType,
    this.count = 0,
    this.flow,
    this.blocksInFlow = 0,
    this.fields = const [],
    this.unpin,
  });

  /// The one block it was opened on, and its type.
  final String? block;
  final String? blockType;

  /// How many blocks are selected.
  final int count;

  /// The flow's id; null: a new flow.
  final String? flow;

  /// How many blocks the flow has (said on the canvas's own menu).
  final int blocksInFlow;
  final List<FlowMenuItemVm> items;

  /// The checklist behind [FlowCommand.fields].
  final List<FlowPinVm> fields;

  /// The row the menu was opened on: [FlowCommand.unpin] takes it off the
  /// block (disabled with its `lockedReason` when it is bound).
  final FlowPinVm? unpin;

  /// The block's id, `3 blocks`, or the flow (`Canvas` for a new one).
  String get title =>
      block ??
      (count > 1 ? S.current.fmBlocks(count) : (flow ?? S.current.fmCanvas));

  /// The block's type, or how many blocks the flow has.
  String get subtitle =>
      blockType ?? (count > 1 ? '' : S.current.fmBlocks(blocksInFlow));

  @override
  List<Object?> get props => [
    block,
    blockType,
    count,
    flow,
    blocksInFlow,
    items,
    fields,
    unpin,
  ];
}

/// Where the context menu of the canvas was opened: on [block] (and its
/// [row]) with the selection [ids], or on the empty canvas.
final class FlowMenuAsk extends Equatable {
  const FlowMenuAsk(this.ids, {this.block, this.row});

  final Set<String> ids;
  final String? block;

  /// The row's place among [block]'s rows.
  final int? row;

  @override
  List<Object?> get props => [ids, block, row];
}

/// The context menu of the flow canvas (spec §13), in the style of the
/// node menu: the name of what it was opened on over its commands, each
/// with its shortcut on the right ([flowHintOf]). `Fields ▸`
/// opens a checklist beside it: a tick pins a field to the block or takes
/// it off ([FlowPinVm.onPin]), and the menu stays open. [onPick] gets a
/// command.
class FlowMenu extends StatefulWidget {
  const FlowMenu({
    required this.vm,
    required this.onPick,
    this.fieldsOpen = false,
    this.mac,
    super.key,
  });

  final FlowMenuVm vm;
  final ValueChanged<FlowCommand> onPick;

  /// Whether the `Fields ▸` checklist is open at first.
  final bool fieldsOpen;

  /// ⌘ glyphs or `Ctrl+`; null: this machine's.
  final bool? mac;

  static const double width = AppSizes.flowMenu;

  /// Shows the menu at [at] (global) and returns the command picked.
  static Future<FlowCommand?> show(
    BuildContext context, {
    required Offset at,
    required FlowMenuVm vm,
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
  late final List<bool> _pinned = [
    for (final f in widget.vm.fields) f.pinned,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final vm = widget.vm;

    Widget panel(List<Widget> children) => Material(
      color: c.ground2,
      elevation: 12,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
        side: BorderSide(color: c.line3),
      ),
      clipBehavior: .antiAlias,
      child: SizedBox(
        width: FlowMenu.width,
        child: SingleChildScrollView(
          padding: Insets.flowMenu,
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
      final reason = i.off?.text ?? unpin?.lockedReason;
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
          height: AppSizes.flowMenuItem,
          color: isFields && _fields ? c.ground4 : null,
          padding: Insets.flowMenuItem,
          child: Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(
                child: Text(
                  unpin == null
                      ? flowCommandLabel(i.command)
                      : S.current.fmUnpinField(unpin.reads),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: FontSizes.md,
                    color: !enabled
                        ? c.muted
                        : (i.danger ? c.badText : c.text1),
                  ),
                ),
              ),
              if (isFields)
                AppIcon(
                  'ui_chevron_right',
                  size: AppSizes.flowMenuChevron,
                  color: c.text3,
                )
              else if (hint.isNotEmpty)
                Row(
                  mainAxisSize: .min,
                  spacing: AppSpacing.flowKeyGlyphs,
                  children: [
                    for (final t in KeyGlyph.tokens(hint))
                      KeyGlyph(t, color: c.text4, size: FontSizes.sm),
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
          if (i.divider)
            Divider(height: AppSizes.flowMenuDivider, color: c.line1),
          if (enabled) row else Tooltip(message: reason, child: row),
        ],
      );
    }

    Widget field(int i, FlowPinVm f) {
      final on = _pinned[i];
      final locked = f.lockedReason != null;
      final onPin = f.onPin;
      final row = InkWell(
        onTap: locked || onPin == null
            ? null
            : () {
                setState(() => _pinned[i] = !on);
                onPin(!on);
              },
        child: Container(
          height: AppSizes.flowMenuField,
          padding: Insets.flowMenuField,
          child: Row(
            spacing: AppSpacing.sm,
            children: [
              Container(
                width: AppSizes.flowMenuTick,
                height: AppSizes.flowMenuTick,
                alignment: .center,
                decoration: BoxDecoration(
                  color: on ? (locked ? c.ground4 : c.emberTint) : null,
                  border: .all(color: on && !locked ? c.ember : c.line3),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadii.chip),
                  ),
                ),
                child: on
                    ? AppIcon(
                        'ui_check',
                        size: AppSizes.flowMenuTickIcon,
                        color: locked ? c.text4 : c.emberSoft,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  f.reads,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontSize: FontSizes.md,
                    color: locked ? c.text3 : c.text1,
                  ),
                ),
              ),
              if (f.lockedReason case final why?)
                Text(
                  why,
                  style: TextStyle(fontSize: FontSizes.xs, color: c.text4),
                ),
            ],
          ),
        ),
      );
      return row;
    }

    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: AppSpacing.xs,
      children: [
        panel([
          Padding(
            padding: Insets.flowMenuTitle,
            child: Row(
              spacing: AppSpacing.sm,
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
                    style: TextStyle(fontSize: FontSizes.sm, color: c.text4),
                  ),
                ),
              ],
            ),
          ),
          for (final i in vm.items) item(i),
        ]),
        if (_fields && vm.fields.isNotEmpty)
          Padding(
            padding: Insets.flowMenuFields,
            child: panel([
              Padding(
                padding: Insets.flowMenuFieldsTitle,
                child: Text(
                  S.current.fmFieldsTitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: FontSizes.xs,
                    fontWeight: .w600,
                    letterSpacing: 0.66,
                    color: c.text4,
                  ),
                ),
              ),
              for (final (i, f) in vm.fields.indexed) field(i, f),
            ]),
          ),
      ],
    );
  }
}
