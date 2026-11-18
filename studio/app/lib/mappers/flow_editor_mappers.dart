import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/drop_point_on_input_action.dart';
import 'package:business/redux/flow_editor/actions/move_blocks_action.dart';
import 'package:business/redux/flow_editor/actions/palette_menu_action.dart';
import 'package:business/redux/flow_editor/actions/pick_palette_entry_action.dart';
import 'package:business/redux/flow_editor/actions/rename_custom_block_action.dart';
import 'package:business/wyrm/flow_view/block_view.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/off.dart';
import 'package:business/wyrm/flow_view/palette_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:business/wyrm/mappers/flow_fields.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:models/field_id.dart';
import 'package:models/flow_edit.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/port_end.dart';
import 'package:models/undo_kind.dart';
import 'package:models/undo_tag.dart';
import 'package:ui/flows/bind_refusal.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/flow_block_view.dart';
import 'package:ui/flows/flow_canvas.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/flow_status.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/models/disabled.dart';

import 'explorer_mappers.dart' show TypeCodeValueType;
import 'field_label_mappers.dart';
import 'rights_mappers.dart';

// The flow editor's business view (business/lib/wyrm/flow_view/) as `ui`
// draws it: one exhaustive switch per domain enum, and builders that only
// map. The words are `ui`'s.

/// Where the draft stands, as the top bar says it.
extension EditorStatusVm on EditorStatus {
  FlowStatusVm get vm => switch (this) {
    EditorStatus.loading => FlowStatusVm.loading,
    EditorStatus.deploying => FlowStatusVm.deploying,
    EditorStatus.draft => FlowStatusVm.draft,
    EditorStatus.deployed => FlowStatusVm.deployed,
  };
}

/// Why Deploy is off.
extension DeployOffReasonVm on DeployOffReason {
  FlowOffReason get vm => switch (this) {
    DeployOffReason.loading => FlowOffReason.loading,
    DeployOffReason.inside => FlowOffReason.deployInside,
    DeployOffReason.nothing => FlowOffReason.nothingToDeploy,
    DeployOffReason.fixFirst => FlowOffReason.fixFirst,
  };
}

/// Why an item of a custom block's menu is off.
extension MyBlockOffReasonVm on MyBlockOffReason {
  /// [used]: the instances of the block (said by `inUse`).
  Disabled vm(int used) => switch (this) {
    MyBlockOffReason.backFirst => const FlowOff(.backFirst),
    MyBlockOffReason.notInLibrary => const FlowOff(.notInLibrary),
    MyBlockOffReason.sameVersion => const FlowOff(.sameVersion),
    MyBlockOffReason.inUse => InUse(used),
    MyBlockOffReason.libraryBusy => const FlowOff(.libraryBusy),
  };
}

/// Why an item of the canvas menu is off.
extension MenuOffReasonVm on MenuOffReason {
  FlowOffReason get vm => switch (this) {
    MenuOffReason.nothingSelected => FlowOffReason.nothingSelected,
    MenuOffReason.needsBroker => FlowOffReason.needsBroker,
    MenuOffReason.nothingToUndo => FlowOffReason.nothingToUndo,
    MenuOffReason.nothingToRedo => FlowOffReason.nothingToRedo,
    MenuOffReason.notCustom => FlowOffReason.notCustom,
  };
}

/// Deploy's [Off] as `ui`'s reason.
extension DeployOffDisabled on Off<DeployOffReason> {
  Disabled get disabled => switch (this) {
    OffFor(:final reason) => FlowOff(reason.vm),
    OffNeeds(:final right) => right.disabled,
  };
}

/// A custom block's menu `Off` as `ui`'s reason; `used` its instances.
extension MyBlockOffDisabled on Off<MyBlockOffReason> {
  Disabled disabled(int used) => switch (this) {
    OffFor(:final reason) => reason.vm(used),
    OffNeeds(:final right) => right.disabled,
  };
}

/// The palette's tabs, both ways.
extension PaletteTabVmOf on PaletteTab {
  PaletteTabVm get vm => switch (this) {
    PaletteTab.blocks => PaletteTabVm.blocks,
    PaletteTab.my => PaletteTabVm.my,
    PaletteTab.tree => PaletteTabVm.tree,
  };
}

extension PaletteTabOf on PaletteTabVm {
  PaletteTab get tab => switch (this) {
    PaletteTabVm.blocks => PaletteTab.blocks,
    PaletteTabVm.my => PaletteTab.my,
    PaletteTabVm.tree => PaletteTab.tree,
  };
}

/// A block's side as its palette chip.
extension PaletteSideKind on PaletteSide {
  PaletteKindVm get kind => switch (this) {
    PaletteSide.input => PaletteKindVm.input,
    PaletteSide.output => PaletteKindVm.output,
    PaletteSide.logic => PaletteKindVm.logic,
  };
}

/// A custom block's menu item, both ways.
extension MyBlockItemOf on MyBlockItem {
  MyBlockItemVm get vm => switch (this) {
    MyBlockItem.edit => MyBlockItemVm.edit,
    MyBlockItem.save => MyBlockItemVm.save,
    MyBlockItem.rename => MyBlockItemVm.rename,
    MyBlockItem.update => MyBlockItemVm.update,
    MyBlockItem.delete => MyBlockItemVm.delete,
    MyBlockItem.removeLibrary => MyBlockItemVm.removeLibrary,
  };
}

extension MyBlockItemVmOf on MyBlockItemVm {
  MyBlockItem get item => switch (this) {
    MyBlockItemVm.edit => MyBlockItem.edit,
    MyBlockItemVm.save => MyBlockItem.save,
    MyBlockItemVm.rename => MyBlockItem.rename,
    MyBlockItemVm.update => MyBlockItem.update,
    MyBlockItemVm.delete => MyBlockItem.delete,
    MyBlockItemVm.removeLibrary => MyBlockItem.removeLibrary,
  };
}

/// A command of the canvas menu as the canvas names it.
extension MenuCommandVm on MenuCommand {
  FlowCommand get vm => switch (this) {
    MenuCommand.cut => FlowCommand.cut,
    MenuCommand.copy => FlowCommand.copy,
    MenuCommand.paste => FlowCommand.paste,
    MenuCommand.duplicate => FlowCommand.duplicate,
    MenuCommand.delete => FlowCommand.delete,
    MenuCommand.selectAll => FlowCommand.selectAll,
    MenuCommand.undo => FlowCommand.undo,
    MenuCommand.redo => FlowCommand.redo,
    MenuCommand.tidy => FlowCommand.tidy,
    MenuCommand.fields => FlowCommand.fields,
    MenuCommand.unpin => FlowCommand.unpin,
    MenuCommand.createCustomBlock => FlowCommand.createCustomBlock,
    MenuCommand.editCustomBlock => FlowCommand.editCustomBlock,
  };
}

/// The edit the store makes of a canvas command; null for the ones the
/// canvas and the page answer themselves (the page asks the name of a new
/// custom block first).
extension FlowCommandEdit on FlowCommand {
  FlowEdit? get edit => switch (this) {
    FlowCommand.copy => FlowEdit.copy,
    FlowCommand.cut => FlowEdit.cut,
    FlowCommand.paste => FlowEdit.paste,
    FlowCommand.duplicate => FlowEdit.duplicate,
    FlowCommand.delete => FlowEdit.delete,
    FlowCommand.undo => FlowEdit.undo,
    FlowCommand.redo => FlowEdit.redo,
    FlowCommand.escape => FlowEdit.escape,
    FlowCommand.tidy => FlowEdit.tidy,
    FlowCommand.editCustomBlock => FlowEdit.editCustomBlock,
    FlowCommand.selectAll ||
    FlowCommand.marquee ||
    FlowCommand.addToSelection ||
    FlowCommand.moveSelection ||
    FlowCommand.nudgeLeft ||
    FlowCommand.nudgeRight ||
    FlowCommand.nudgeUp ||
    FlowCommand.nudgeDown ||
    FlowCommand.unbind ||
    FlowCommand.pan ||
    FlowCommand.zoom ||
    FlowCommand.zoomIn ||
    FlowCommand.zoomOut ||
    FlowCommand.zoomReset ||
    FlowCommand.zoomFit ||
    FlowCommand.viewValue ||
    FlowCommand.searchPalette ||
    FlowCommand.deploy ||
    FlowCommand.help ||
    FlowCommand.fields ||
    FlowCommand.unpin ||
    FlowCommand.createCustomBlock => null,
  };
}

/// A custom block's name or ports refused, as the dialogs say it.
extension BlockNameProblemVm on BlockNameProblem {
  CustomBlockProblemVm get vm => switch (this) {
    BlockNameProblem.name => CustomBlockProblemVm.badName,
    BlockNameProblem.taken => CustomBlockProblemVm.taken,
    BlockNameProblem.port => CustomBlockProblemVm.badPort,
    BlockNameProblem.duplicate => CustomBlockProblemVm.duplicate,
    BlockNameProblem.limit => CustomBlockProblemVm.limit,
  };
}

/// A scope refused, as the prompt says it.
extension ScopeProblemVmOf on ScopeProblem {
  ScopeProblemVm get vm => switch (this) {
    ScopeProblem.empty => ScopeProblemVm.empty,
    ScopeProblem.section => ScopeProblemVm.section,
    ScopeProblem.otherSite => ScopeProblemVm.otherSite,
    ScopeProblem.segment => ScopeProblemVm.segment,
  };
}

/// What placing [entry] at [place] does: a tap or a drop on the canvas
/// places a block; a point let go on an input is a block that reads it,
/// wired into that input. Null: nothing (only a point drops on an input).
Action? placeActionOf(PaletteEntry entry, Place place) =>
    switch ((entry, place)) {
      (_, PlaceTapped()) => PickPaletteEntryAction(entry),
      (_, PlaceOnCanvas(:final x, :final y, :final write)) =>
        PickPaletteEntryAction(entry, x: x, y: y, write: write),
      (PointPick(:final key), PlaceOnInput(:final block, :final port)) =>
        DropPointOnInputAction(key, PortEnd(block, port)),
      (EnginePick() || LibraryPick() || ActionPick(), PlaceOnInput()) => null,
    };

/// A block type of the catalogue as a palette entry.
extension CatalogEntryVm on CatalogEntry {
  PaletteEntryVm get vm => PaletteEntryVm(
    title: title,
    kind: side.kind,
    category: category,
    wire: type.wire,
    description: description,
  );
}

/// A custom block of this flow as a palette entry, with its menu.
extension MyBlockEntryVm on MyBlockEntry {
  PaletteEntryVm get vm => PaletteEntryVm(
    title: name,
    kind: PaletteKindVm.my,
    description: description,
    instances: used,
    updateTo: updateTo,
    insideItself: insideItself,
    menu: [
      for (final m in menu)
        PaletteMenuItemVm(m.item.vm, off: m.off?.disabled(used)),
    ],
  );
}

/// A block of the site's library as a palette entry, with its menu.
extension LibraryEntryVm on LibraryEntry {
  PaletteEntryVm get vm => PaletteEntryVm(
    title: name,
    kind: PaletteKindVm.library,
    description: description,
    version: version,
    insideItself: insideItself,
    menu: [
      PaletteMenuItemVm(
        MyBlockItemVm.removeLibrary,
        off: removeOff?.disabled(0),
      ),
    ],
  );
}

/// A row of the Tree tab; `root` the site's root (the node icons).
extension TreeEntryVm on TreeEntry {
  PaletteTreeRowVm vm(String root) => switch (this) {
    TreeNodeEntry(:final type) && final n => PaletteNodeRowVm(
      key: key,
      name: name,
      depth: depth,
      icon: AppIcon.nodeName(
        key: key,
        root: root,
        profile: n.profile,
        value: type != null,
      ),
      opens: n.opens,
      open: n.open,
      used: n.used,
      type: type?.valueType,
      value: n.value,
      places: n.entry != null,
      writable: n.writable,
    ),
    TreeActionEntry(:final node, :final action, :final inputs) =>
      PaletteActionRowVm(
        key: key,
        name: name,
        depth: depth,
        node: node,
        action: action,
        inputs: inputs,
      ),
  };

  /// What the row places; null: it opens or closes.
  PaletteEntry? get entry => switch (this) {
    final TreeNodeEntry n => n.entry,
    final TreeActionEntry a => a.entry,
  };
}

/// The canvas menu as `ui` draws it.
extension FlowMenuViewVm on FlowMenuView {
  /// [pin] pins a field of the menu's block (true) or takes it off.
  FlowMenuVm vm(ValueChanged<bool> Function(FieldId field) pin) => FlowMenuVm(
    block: block,
    blockType: blockType,
    count: count,
    flow: flow,
    blocksInFlow: blocksInFlow,
    fields: [for (final f in fields) f.vm(pin(f.id))],
    unpin: unpin?.vm(pin(unpin!.id)),
    items: [
      for (final i in items)
        FlowMenuItemVm(
          i.command.vm,
          off: switch (i.off) {
            final r? => FlowOff(r.vm),
            null => null,
          },
          danger: i.danger,
          divider: i.divider,
        ),
    ],
  );
}

extension MenuPinViewVm on MenuPinView {
  FlowPinVm vm(ValueChanged<bool> onPin) => FlowPinVm(
    label: label.data,
    word: label.word,
    pinned: pinned,
    locked: locked,
    onPin: onPin,
  );
}

/// What `Create custom block…` proposes.
extension CustomBlockViewVm on CustomBlockView {
  CustomBlockDialogVm get vm => CustomBlockDialogVm(
    blocks: blocks,
    name: name,
    inputs: [for (final p in inputs) p.vm],
    outputs: [for (final p in outputs) p.vm],
  );
}

extension CustomPortViewVm on CustomPortView {
  BlockPortVm get vm =>
      BlockPortVm(name: name, outside: [for (final o in outside) o.wire]);
}

/// The scope prompt on its row.
extension ScopePromptViewVm on ScopePromptView {
  ScopePromptVm get vm => ScopePromptVm(
    block: block,
    row: place,
    value: value,
    suggestions: suggestions.unlock,
  );
}

// ---------- the canvas ----------

/// What a block is, as its header chip says it.
extension BlockRoleVm on BlockRole {
  BlockKindVm get vm => switch (this) {
    BlockRole.node => BlockKindVm.node,
    BlockRole.logic => BlockKindVm.logic,
    BlockRole.sink => BlockKindVm.sink,
    BlockRole.action => BlockKindVm.action,
    BlockRole.custom => BlockKindVm.my,
  };
}

/// The inputs or outputs block of an inside view.
extension BoundaryVmOf on Boundary {
  BoundaryVm get vm => switch (this) {
    Boundary.inputs => BoundaryVm.inputs,
    Boundary.outputs => BoundaryVm.outputs,
  };
}

/// What a sink would do in the preview.
extension GhostKindVmOf on GhostKind {
  GhostKindVm get vm => switch (this) {
    GhostKind.send => GhostKindVm.send,
    GhostKind.run => GhostKindVm.run,
    GhostKind.write => GhostKindVm.write,
  };
}

/// How a row's value is drawn.
extension RowToneVm on RowTone {
  ValueTone get vm => switch (this) {
    RowTone.plain => ValueTone.plain,
    RowTone.bound => ValueTone.bound,
    RowTone.bad => ValueTone.bad,
    RowTone.stale => ValueTone.stale,
    RowTone.ghost => ValueTone.ghost,
  };
}

/// A port's mark.
extension PortMarkKindVm on PortMarkKind {
  PortMark get vm => switch (this) {
    PortMarkKind.none => PortMark.none,
    PortMarkKind.free => PortMark.free,
    PortMarkKind.bound => PortMark.bound,
    PortMarkKind.write => PortMark.write,
  };
}

/// What − and + change.
extension VariadicKindVmOf on VariadicKind {
  VariadicKindVm get vm => switch (this) {
    VariadicKind.ports => VariadicKindVm.ports,
    VariadicKind.pairs => VariadicKindVm.pairs,
    VariadicKind.inputs => VariadicKindVm.inputs,
  };
}

extension VariadicViewVm on VariadicView {
  VariadicVm get vm => VariadicVm(kind.vm, count: count, canRemove: canRemove);
}

/// A row of a block on the canvas; its key is its field's id written out
/// (the widgets' identity, never read back).
extension RowViewVm on RowView {
  FieldRowVm get vm => FieldRowVm(
    id: id.key,
    label: label.data,
    word: label.word,
    name: name,
    value: value,
    ghost: ghost?.vm,
    tone: tone.vm,
    inPort: inPort,
    outPort: outPort,
    outAliases: outAliases.unlock,
    inMark: inMark.vm,
    outMark: outMark.vm,
    editScope: editScope,
    command: command,
  );
}

/// A block on the canvas.
/// The render model made of each block view, kept while the view is the
/// same object: a block that did not change is drawn from the same model,
/// so the canvas can leave it as it is.
final _blockVms = Expando<FlowBlockVm>('FlowBlockVm of a BlockView');

extension BlockViewVm on BlockView {
  FlowBlockVm get vm => _blockVms[this] ??= _vm;

  FlowBlockVm get _vm => FlowBlockVm(
    id: id,
    boundary: boundary?.vm,
    caption: caption.unlock,
    kind: role.vm,
    x: x,
    y: y,
    width: width,
    selected: selected,
    preview: ghost,
    openable: openable,
    rows: [for (final r in rows) r.vm],
    variadic: variadic?.vm,
  );
}

/// A wire on the canvas.
extension WireViewVm on WireView {
  FlowWireVm get vm => FlowWireVm(
    from,
    fromPort,
    to,
    toPort,
    writes: writes,
    firesAtDeploy: firesAtDeploy,
  );
}

/// Why a row does not take a dragged wire.
extension WireRefusalVm on WireRefusal {
  BindRefusalVm get vm => switch (refused.reason) {
    BindRefusal.output => const RefuseOutput(),
    BindRefusal.noInput => RefuseNoInput(label.data, word: label.word),
    BindRefusal.self => const RefuseSelf(),
    BindRefusal.type => RefuseType(
      refused.from?.wire ?? '',
      refused.to?.wire ?? '',
    ),
    BindRefusal.loop => const RefuseLoop(),
    BindRefusal.needsBroker => RefuseNeedsBroker(
      label.data,
      word: label.word,
    ),
  };
}

/// The output end a wire is dragged from.
extension FieldRefEnd on FieldRefVm {
  PortEnd get end => PortEnd(block, port);
}

/// The input end of a wire.
extension PortRefEnd on PortRefVm {
  PortEnd get end => PortEnd(block, port);
}

/// Blocks let go at new corners, as the move they are (a nudge is one step
/// of the undo history with the next nudges).
extension BlocksMovedAction on BlocksMoved {
  MoveBlocksAction get action => MoveBlocksAction({
    for (final MapEntry(:key, :value) in to.entries) key: (value.dx, value.dy),
  }, tag: nudge ? const UndoTag(UndoKind.nudge) : null);
}

/// What the create dialog handed back, as the block to make.
extension CustomBlockResultSpec on CustomBlockResult {
  CustomBlockSpec get spec => customBlockSpecOf(
    name: name,
    description: description,
    inputs: inputs,
    outputs: outputs,
    defaults: defaults,
  );
}

/// The palette of the flow editor, as the tab shown draws it, and what a
/// gesture on one of its entries or rows (each by its place) does.
extension FlowViewPalette on FlowView {
  /// The entries of the Blocks or the My blocks tab ([paletteEntryAt]).
  IList<PaletteEntryVm> get paletteVms => switch (palette) {
    PaletteTab.tree => const IListConst([]),
    PaletteTab.my => [
      for (final m in myBlocks) m.vm,
      for (final l in library) l.vm,
    ].lock,
    PaletteTab.blocks => [for (final c in catalog) c.vm].lock,
  };

  /// The rows of the Tree tab; null on the other tabs.
  IList<PaletteTreeRowVm>? get treeVms => switch (tree) {
    final rows? => [for (final e in rows) e.vm(root)].lock,
    null => null,
  };

  /// What placing the entry [p] reports does; null: nothing.
  Action? placing(EntryPlaced p) => switch (paletteEntryAt(p.entry)) {
    final e? => placeActionOf(e, p.place),
    null => null,
  };

  /// What placing the Tree tab's row [p] reports does; null: nothing.
  Action? placingRow(TreeRowPlaced p) => switch (tree?.elementAtOrNull(p.row)) {
    final e? => switch (e.entry) {
      final entry? => placeActionOf(entry, p.place),
      null => null,
    },
    null => null,
  };

  /// What a pick in an entry's menu does.
  Action? menuPick(EntryMenuPicked p) => switch (paletteNameAt(p.entry)) {
    final name? => PaletteMenuAction(name, p.item.item),
    null => null,
  };

  /// What a custom block's new name does.
  Action? renaming(EntryRenamed r) => switch (paletteNameAt(r.entry)) {
    final name? => RenameCustomBlockAction(name, r.name),
    null => null,
  };
}
