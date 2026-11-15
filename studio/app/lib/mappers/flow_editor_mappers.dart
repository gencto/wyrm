import 'package:business/redux/common/action.dart';
import 'package:business/redux/flow_editor/actions/drop_point_on_input_action.dart';
import 'package:business/redux/flow_editor/actions/pick_palette_entry_action.dart';
import 'package:business/wyrm/flow_view/flow_view.dart';
import 'package:business/wyrm/flow_view/menu_view.dart';
import 'package:business/wyrm/flow_view/off.dart';
import 'package:business/wyrm/flow_view/palette_view.dart';
import 'package:business/wyrm/flow_view/prompt_view.dart';
import 'package:business/wyrm/mappers/flow_blocks.dart';
import 'package:flutter/foundation.dart';
import 'package:models/flow_edit.dart';
import 'package:models/palette_entry.dart';
import 'package:models/palette_tab.dart';
import 'package:models/port_end.dart';
import 'package:ui/flows/block_palette.dart';
import 'package:ui/flows/custom_block_dialog.dart';
import 'package:ui/flows/flow_intents.dart';
import 'package:ui/flows/flow_menu.dart';
import 'package:ui/flows/flow_status.dart';
import 'package:ui/flows/scope_prompt.dart';
import 'package:ui/flows/shortcut_card.dart';
import 'package:ui/indicators/app_icon.dart';
import 'package:ui/models/disabled.dart';

import 'explorer_mappers.dart' show TypeCodeValueType;
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
  PaletteEntryVm vm(ValueChanged<Place> place) => PaletteEntryVm(
    title: title,
    place: place,
    kind: side.kind,
    category: category,
    wire: type.wire,
    description: description,
  );
}

/// A custom block of this flow as a palette entry, with its menu.
extension MyBlockEntryVm on MyBlockEntry {
  PaletteEntryVm vm({
    required ValueChanged<Place> place,
    required ValueChanged<MyBlockItemVm> onMenu,
    required ValueChanged<String> onRename,
  }) => PaletteEntryVm(
    title: name,
    place: place,
    kind: PaletteKindVm.my,
    description: description,
    instances: used,
    updateTo: updateTo,
    insideItself: insideItself,
    menu: [
      for (final m in menu)
        PaletteMenuItemVm(m.item.vm, off: m.off?.disabled(used)),
    ],
    onMenu: onMenu,
    onRename: onRename,
  );
}

/// A block of the site's library as a palette entry, with its menu.
extension LibraryEntryVm on LibraryEntry {
  PaletteEntryVm vm({
    required ValueChanged<Place> place,
    required ValueChanged<MyBlockItemVm> onMenu,
  }) => PaletteEntryVm(
    title: name,
    place: place,
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
    onMenu: onMenu,
  );
}

/// A row of the Tree tab; `root` the site's root (the node icons).
extension TreeEntryVm on TreeEntry {
  PaletteTreeRowVm vm(String root, ValueChanged<Place> place) => switch (this) {
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
      place: n.entry == null ? null : place,
      writable: n.writable,
    ),
    TreeActionEntry(:final node, :final action, :final inputs) =>
      PaletteActionRowVm(
        key: key,
        name: name,
        depth: depth,
        node: node,
        action: action,
        place: place,
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
  FlowMenuVm get vm => FlowMenuVm(
    block: block,
    blockType: blockType,
    count: count,
    flow: flow,
    blocksInFlow: blocksInFlow,
    fields: [for (final f in fields) f.vm],
    unpin: unpin?.vm,
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
  FlowPinVm get vm =>
      FlowPinVm(id: id.key, label: label, pinned: pinned, locked: locked);
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
    row: row.key,
    value: value,
    suggestions: suggestions.unlock,
  );
}
