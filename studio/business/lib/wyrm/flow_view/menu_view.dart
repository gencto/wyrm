import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_edge.dart';

import '../mappers/flow_blocks.dart';
import '../mappers/flow_fields.dart';

/// A command of the canvas's context menu (spec §13).
enum MenuCommand {
  cut,
  copy,
  paste,
  duplicate,
  delete,
  selectAll,
  undo,
  redo,
  tidy,
  fields,
  unpin,
  createCustomBlock,
  editCustomBlock,
}

/// Why an item of the context menu is off.
enum MenuOffReason {
  /// Nothing (but the inputs and outputs blocks) is selected.
  nothingSelected,

  /// The broker has no custom blocks (ADR 0040 §3).
  needsBroker,
  nothingToUndo,
  nothingToRedo,

  /// The block is no instance of a custom block.
  notCustom,
}

/// Where the context menu opened: on [block] (and its [row]) with the
/// selection [ids], or on the empty canvas.
final class MenuAsk extends Equatable {
  const MenuAsk(this.ids, {this.block, this.row});

  final ISet<String> ids;
  final String? block;
  final RowId? row;

  @override
  List<Object?> get props => [ids, block, row];
}

/// One item of the context menu.
final class MenuItemView extends Equatable {
  const MenuItemView(
    this.command, {
    this.off,
    this.divider = false,
    this.danger = false,
  });

  final MenuCommand command;
  final MenuOffReason? off;

  /// A line above it.
  final bool divider;
  final bool danger;

  @override
  List<Object?> get props => [command, off, divider, danger];
}

/// A field in the menu's `Fields ▸` checklist (or its `Unpin`).
final class MenuPinView extends Equatable {
  const MenuPinView({
    required this.id,
    required this.label,
    required this.pinned,
    required this.locked,
  });

  final FieldId id;
  final String label;
  final bool pinned;

  /// Bound: it stays on the block.
  final bool locked;

  @override
  List<Object?> get props => [id, label, pinned, locked];
}

/// The context menu (spec §13).
final class FlowMenuView extends Equatable {
  const FlowMenuView({
    required this.count,
    required this.items,
    this.block,
    this.blockType,
    this.flow,
    this.blocksInFlow = 0,
    this.fields = const IListConst([]),
    this.unpin,
  });

  /// The one block it opened on; null: the selection or the canvas.
  final String? block;

  /// That block's type (its engine name).
  final String? blockType;

  /// How many blocks are selected.
  final int count;

  /// The canvas draft's id; null when it has none.
  final String? flow;

  /// How many blocks the canvas holds.
  final int blocksInFlow;

  /// The fields of [block], pinned or not.
  final IList<MenuPinView> fields;

  /// The field the menu opened on, to take off the block.
  final MenuPinView? unpin;
  final IList<MenuItemView> items;

  @override
  List<Object?> get props => [
    block,
    blockType,
    count,
    flow,
    blocksInFlow,
    fields,
    unpin,
    items,
  ];
}

/// The context menu [ask] opens on draft [d] (its blocks' [fields]).
FlowMenuView flowMenuOf(
  MenuAsk ask,
  FlowDraft? d,
  Map<String, List<FlowField>> fields, {
  required bool customBlocks,
  required bool canUndo,
  required bool canRedo,
}) {
  final ids = ask.ids;
  final block = ask.block;
  final b = block == null ? null : d?.blocks[block];
  final edges = d?.edges ?? const IListConst<FlowEdge>([]);
  final real = {
    for (final id in ids)
      if (!isBoundary(id)) id,
  };
  final none = real.isEmpty ? MenuOffReason.nothingSelected : null;
  final one = ids.length == 1 && b != null;
  final noBlocks = customBlocks ? null : MenuOffReason.needsBroker;
  MenuPinView pinOf(FlowField f) => MenuPinView(
    id: f.id,
    label: f.label,
    pinned: fieldPinned(b!, f, edges),
    locked: fieldBound(b, f, edges),
  );
  final own = one ? fields[b.id] ?? const <FlowField>[] : const <FlowField>[];
  final onRow = ask.row == null
      ? null
      : own.where((f) => f.id == ask.row).firstOrNull;
  return FlowMenuView(
    block: one ? b.id : null,
    blockType: one ? b.type.wire : null,
    count: ids.length,
    flow: d == null || d.id.isEmpty ? null : d.id,
    blocksInFlow: d?.blocks.length ?? 0,
    fields: [for (final f in own) pinOf(f)].lock,
    unpin: onRow == null ? null : pinOf(onRow),
    items: [
      MenuItemView(MenuCommand.cut, off: none),
      MenuItemView(MenuCommand.copy, off: none),
      const MenuItemView(MenuCommand.paste),
      MenuItemView(MenuCommand.duplicate, off: none),
      MenuItemView(MenuCommand.delete, off: none, danger: ids.isNotEmpty),
      const MenuItemView(MenuCommand.selectAll, divider: true),
      if (ids.isEmpty) ...[
        MenuItemView(
          MenuCommand.undo,
          divider: true,
          off: canUndo ? null : MenuOffReason.nothingToUndo,
        ),
        MenuItemView(
          MenuCommand.redo,
          off: canRedo ? null : MenuOffReason.nothingToRedo,
        ),
        const MenuItemView(MenuCommand.tidy, divider: true),
      ],
      if (one) ...[
        const MenuItemView(MenuCommand.fields, divider: true),
        if (onRow != null) const MenuItemView(MenuCommand.unpin),
      ],
      // Custom blocks (ADR 0040 §3): a selection becomes one; an instance
      // opens its inside. Off, with the reason, on a broker without them.
      if (ids.isNotEmpty)
        MenuItemView(
          MenuCommand.createCustomBlock,
          divider: true,
          off: noBlocks ?? none,
        ),
      if (one)
        MenuItemView(
          MenuCommand.editCustomBlock,
          off:
              noBlocks ?? (isInstance(b.type) ? null : MenuOffReason.notCustom),
        ),
    ].lock,
  );
}
