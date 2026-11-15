import 'package:flutter/widgets.dart';

/// Sizes of components the canvas repeats — layer 3 of the theme strategy
/// (see `common.dart`). A size two widgets share is here, named for the
/// component.
abstract final class AppSizes {
  /// A dialog's width (Account › Security, the backup and update sheets).
  static const double dialog = 680;

  /// The tallest a dialog grows before it scrolls.
  static const double dialogMaxHeight = 900;

  /// A menu's width (the account menu, a node's menu).
  static const double menu = 300;

  /// The Assistant drawer over Explorer (⌘J, board *AssistantDrawer*).
  static const double assistantDrawer = 420;

  /// The height of a log or a table shown inside a card or a dialog.
  static const double logPane = 260;

  /// The width of a dialog that shows a log or a history.
  static const double logDialog = 480;

  /// The height of the log-in and unlock buttons.
  static const double tallButton = 50;

  /// A button beside a boxed field, as tall as the field.
  static const double fieldButton = 46;

  /// The outlined buttons of the offer (`Not now`, `Don't ask`).
  static const double outlinedButton = 42;

  /// The row of *Probe a range*: its fields and its button.
  static const double probeRow = 38;

  /// The port field of *Probe a range*.
  static const double portField = 70;

  /// The step-up dialog's width (board `UnlockStepUp`).
  static const double stepUpDialog = 520;

  /// The line of a legend of the hero (14 × 2).
  static const heroLegend = Size(14, 2);

  // ---- the log-in page (login.md §1) ----

  /// The top band of the log-in page that drags the window.
  static const double windowDrag = 40;

  /// The form panel beside the hero, and while *Find on this network* or
  /// the trust card is open (the boards *Discover…*: 40 more).
  static const double logInPanel = 520;
  static const double logInPanelFinding = 560;

  /// The form's widest, and while finding.
  static const double logInForm = 420;
  static const double logInFormFinding = 460;

  /// The hero above the form, below 1080 and below 700 px wide.
  static const double heroStacked = 420;
  static const double heroSmall = 220;

  /// The tile of the offer's glyph, and the glyph in it (the key a little
  /// smaller).
  static const double offerTile = 84;
  static const double offerGlyph = 44;
  static const double offerKey = 40;

  /// The initials of the unlock's account card.
  static const double avatar = 44;

  /// A bullet's dot and a status dot on a line of text.
  static const double dot = 6;

  /// The tile of the step-up's device row, and its glyph.
  static const double stepUpTile = 48;
  static const double stepUpGlyph = 26;

  /// A small outlined button at the end of a row or a line.
  static const double smallButton = 32;

  /// A small button inside a list row.
  static const double rowButton = 30;

  /// The board's switch (40 × 22) and its knob.
  static const double switchWidth = 40;
  static const double switchHeight = 22;
  static const double switchKnob = 16;

  /// The square tile that names a device's platform.
  static const double deviceTile = 34;

  /// The board's ▾ caret of a drop-down.
  static const caret = Size(7, 5);

  /// A tile of the gallery page.
  static const double galleryTile = 380;

  /// The plot of System's *Router traffic* (board `System`).
  static const double trafficPlot = 120;

  // The flow editor (studio/docs/design/specs/flow-editor.md).

  /// The flow editor's top bar, at its least.
  static const double flowTopBar = 52;

  /// The width the block palette opens with.
  static const double flowPalette = 220;

  /// The width the flow inspector opens with.
  static const double flowInspector = 320;

  /// The widest the flow's state in the top bar grows.
  static const double flowStateText = 320;

  /// A small status dot: the flow's state in the top bar, a problem of the
  /// flow summary.
  static const double flowDot = 6;

  /// A block on the canvas (spec §3: 200–220): its width, its header, one
  /// field row, the room above the first row, and the − / + row.
  static const double flowBlockWidth = 220;
  static const double flowBlockHeader = 32;
  static const double flowBlockRow = 28;
  static const double flowBlockBodyTop = 6;
  static const double flowBlockTools = 38;

  /// The port on the edge of a block's row.
  static const double flowPort = 10;

  /// The − / + button of a block whose fields can be added.
  static const double flowToolButton = 28;

  /// The widest a block row's command button grows.
  static const double flowCommandMaxWidth = 140;

  /// The widest a block row's label grows before its value.
  static const double flowRowLabelMaxWidth = 124;

  /// The warning chip on a wire, and how tall the chip under a dragged
  /// wire that says why a row refuses it is.
  static const double flowWarnChip = 22;
  static const double flowWarnChipWidth = 120;
  static const double flowRefusal = 24;

  /// A button of the canvas tools (the zoom, the `?`); the `?` is square.
  static const double flowCanvasTool = 34;

  /// The line and the ring of the canvas legend.
  static const flowLegendLine = Size(18, 2);
  static const double flowLegendRing = 9;

  /// A one-line field of the flow editor: the palette's search, a field of
  /// the custom block dialog, the scope prompt's scope.
  static const double flowField = 34;

  /// The field of the dialog that asks for a name.
  static const double flowNameField = 36;

  /// The custom block dialog at its largest, and the name dialog's width.
  static const double flowBlockDialogWidth = 520;
  static const double flowBlockDialogMaxHeight = 640;
  static const double flowNameDialog = 380;

  /// A row of the block palette: a block type, a point, a dragged entry.
  static const double flowPaletteRow = 32;

  /// A category header of the block palette.
  static const double flowPaletteGroup = 34;

  /// The tag chip before a block type's name in the palette.
  static const flowPaletteTag = Size(24, 16);

  /// The tag before a point's name in the palette's Tree tab.
  static const double flowPaletteTreeTag = 22;

  /// The widest a palette row's value grows: a block type's, a point's.
  static const double flowPaletteValue = 84;
  static const double flowPaletteTreeValue = 90;

  /// A command of a flow editor menu: the canvas menu, a palette entry's
  /// menu, `Read` / `Write` of a dropped point.
  static const double flowMenuItem = 34;

  /// The canvas menu's width, a field of its `Fields ▸` checklist, the tick
  /// box of that field, and the line between two groups of commands.
  static const double flowMenu = 260;
  static const double flowMenuField = 30;
  static const double flowMenuTick = 16;
  static const double flowMenuDivider = 9;

  /// A control of a flow inspector field: a text, a choice, a bound value,
  /// a toggle, a cell of a list editor, a suggest field.
  static const double flowControl = 32;

  /// The label column of an inspector field: without a pin, and beside one.
  static const double flowInspectorLabel = 104;
  static const double flowInspectorPinnedLabel = 86;

  /// The pin before an inspector field's label.
  static const double flowInspectorPin = 18;

  /// An icon button of an inspector field: its link, its view, a suggest
  /// field's menu.
  static const double flowInspectorButton = 28;

  /// An inspector field's row, and a fact of the flow summary, at least.
  static const double flowInspectorRow = 44;
  static const double flowInspectorFact = 36;

  /// The menu item of an inspector field's link button.
  static const double flowLinkMenuItem = 36;

  /// The unit box of a duration field.
  static const double flowUnitBox = 64;

  /// The remove button at the end of a list editor's row.
  static const double flowRowsRemove = 24;

  /// A suggest field's menu: an item, the menu at its tallest and at its
  /// narrowest.
  static const double flowSuggestItem = 32;
  static const double flowSuggestMenuMaxHeight = 360;
  static const double flowSuggestMenuMinWidth = 200;

  /// The scope prompt's card.
  static const double flowScopePrompt = 320;

  /// The shortcut card at its widest, the keys of one command at their
  /// widest, and a key chip.
  static const double flowShortcutCard = 760;
  static const double flowShortcutKeys = 216;
  static const double flowKeyChip = 22;

  // The flow editor's glyphs (`AppIcon` sizes), by where they stand.

  /// The magnifier of the palette's search box.
  static const double flowSearchIcon = 14;

  /// The chevron of a palette group that opens or closes it.
  static const double flowGroupChevron = 12;

  /// The pin before an inspector field's label.
  static const double flowPinIcon = 14;

  /// The link and view glyphs of an inspector field.
  static const double flowInspectorIcon = 16;

  /// The chevron of an inspector choice field.
  static const double flowChoiceChevron = 16;

  /// The chevron of a small drop-down: a duration's unit, a list editor's
  /// cell, a suggest field's menu.
  static const double flowDropChevron = 14;

  /// The chevron of a block's `Open inside` link row.
  static const double flowLinkChevron = 12;

  /// The ▶ of a block's command input.
  static const double flowCommandIcon = 10;

  /// The action button's glyph at the end of a block row.
  static const double flowRowActionIcon = 12;

  /// The chevron of the canvas menu's `Fields ▸`.
  static const double flowMenuChevron = 14;

  /// The tick in a field's box of the `Fields ▸` checklist.
  static const double flowMenuTickIcon = 12;

  /// The × that removes a list editor's row.
  static const double flowRowsRemoveIcon = 14;

  /// The × of the shortcut card.
  static const double flowCardClose = 16;

  /// The × that closes the flow editor, in its top bar.
  static const double flowEditorClose = 18;
}
