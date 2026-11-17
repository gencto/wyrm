import 'package:flutter/widgets.dart';

import 'typography.dart';

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
  static const flowSearchIcon = IconSize._(14);

  /// The chevron of a palette group that opens or closes it.
  static const flowGroupChevron = IconSize._(12);

  /// The pin before an inspector field's label.
  static const flowPinIcon = IconSize._(14);

  /// The link and view glyphs of an inspector field.
  static const flowInspectorIcon = IconSize._(16);

  /// The chevron of an inspector choice field.
  static const flowChoiceChevron = IconSize._(16);

  /// The chevron of a small drop-down: a duration's unit, a list editor's
  /// cell, a suggest field's menu.
  static const flowDropChevron = IconSize._(14);

  /// The chevron of a block's `Open inside` link row.
  static const flowLinkChevron = IconSize._(12);

  /// The ▶ of a block's command input.
  static const flowCommandIcon = IconSize._(10);

  /// The action button's glyph at the end of a block row.
  static const flowRowActionIcon = IconSize._(12);

  /// The chevron of the canvas menu's `Fields ▸`.
  static const flowMenuChevron = IconSize._(14);

  /// The tick in a field's box of the `Fields ▸` checklist.
  static const flowMenuTickIcon = IconSize._(12);

  /// The × that removes a list editor's row.
  static const flowRowsRemoveIcon = IconSize._(14);

  /// The × of the shortcut card.
  static const flowCardClose = IconSize._(16);

  /// The × that closes the flow editor, in its top bar.
  static const flowEditorClose = IconSize._(18);

  /// The height of a package's manifest under its checks (Add a link ›
  /// Check).
  static const double manifestView = 220;

  /// The audit tail of Access, as tall as its tables are long.
  static const double auditTail = 560;

  /// A row of Access's users and grants: one line, roomier than a point's.
  static const double accessRow = 48;

  /// A dialog with a form of a few fields (Access's users and grants).
  static const double formDialog = 520;

  /// A dialog with a broker's own form (Sites' upstream and token).
  static const double wideFormDialog = 640;

  /// The Assistant's mark in the head of its drawer.
  static const assistantMark = IconSize._(15);

  /// The mark of a guide card beside its title.
  static const guideMark = IconSize._(28);

  /// The tone square of a panel that failed, and the one that stands for
  /// the whole card in a box too small for it.
  static const double faultSquare = 36;
  static const double faultSquareSmall = 28;

  /// The token Sites shows once it is issued.
  static const double tokenLog = 180;

  /// The mark of a step of a task: done, running, waiting.
  static const double stepMark = 20;

  /// The bar of a task's progress.
  static const double progressBar = 8;

  /// The sign before a line of a change (`+`, `−`).
  static const double changeSign = 14;

  /// A segment of the task sheet's choice, and a field of the sheet.
  static const double sheetSegment = 34;
  static const double sheetField = 40;

  /// The row that opens and closes the details of an error.
  static const double errorDetailsToggle = 36;

  /// The columns of a line of the log: its time, its level, its target.
  static const double logTime = 80;
  static const double logLevel = 56;
  static const double logTarget = 170;

  /// The bar above Explorer's points: the filter and the marked count.
  static const double pointsBar = 40;

  /// The filter of the table grid, and its menu button.
  static const gridFilter = Size(200, 30);
  static const double gridMenuButton = 32;

  /// The track of a segmented control: around its segments and between
  /// them; an icon segment, and the tallest a text segment grows before
  /// the row scrolls.
  static const double segmentTrackInset = 2;
  static const double segmentGap = 3;
  static const double segmentIconWidth = 32;
  static const double segmentHeight = 26;
  static const double segmentMaxHeight = 44;

  /// A line of the log.
  static const double logRow = 30;

  /// Between the tiles of System's grid.
  static const double sysTileGap = 12;

  /// The widest a form of the log-in column grows.
  static const double authForm = 340;

  /// A spinner set in a line of text.
  static const double inlineSpinner = 12;

  /// The mark of a step of the log-in.
  static const double loginStepMark = 16;

  /// The square a small icon button is tapped in: a toast's close, a key
  /// line's copy, the Problems drawer's close, the error dialog's close,
  /// a field's eye, the review panel's close.
  static const double toastClose = 26;
  static const double keyCopy = 28;
  static const double problemsClose = 30;
  static const double errorClose = 32;
  static const double fieldEye = 36;
  static const double reviewClose = 40;
}

/// The sizes an icon is drawn at (board *Icons*: the set is drawn on 24 and
/// read down to 12). A scale, like `AppSpacing`: a step says where a size
/// sits, not what the icon is. An icon a component sizes by itself has its
/// own name in [AppSizes].
/// The size an icon is drawn at: one of [IconSizes], or a component's own
/// icon size of [AppSizes]. It is a `double` wherever one is read, and it
/// is made only in this file, so a parameter of this type takes a token
/// and never a number.
extension type const IconSize._(double _value) implements double {}

abstract final class IconSizes {
  /// The tick inside a small check box.
  static const tick = IconSize._(10);

  /// An icon set in a line of the smallest text, at its size.
  static const inline = IconSize._(11);

  static const xs = IconSize._(12);
  static const sm = IconSize._(14);
  static const md = IconSize._(16);
  static const lg = IconSize._(18);
  static const xl = IconSize._(20);
  static const xxl = IconSize._(24);
}

/// The sizes of the mark of a state or a quality (a dot, a ring, a dashed
/// ring), each with the size of the icon that stands in its place (a
/// check, a cross): the icon is drawn four points larger, so its stroke
/// reads as the dot does.
enum MarkSize {
  /// In a dense pill and a task row.
  small(6, IconSize._(10)),

  /// Beside a word: a quality, a state, a step.
  regular(8, IconSize._(12)),

  /// The choice of a card.
  large(12, IconSize._(16));

  const MarkSize(this.side, this.icon);

  final double side;
  final IconSize icon;
}

/// The sizes a key of a shortcut is printed at: its word in mono, and the
/// icon that stands for a glyph the fonts do not hold, drawn two points
/// larger so it reads as tall as the word.
enum KeyGlyphSize {
  /// On the shortcut card.
  small(FontSizes.xs, IconSize._(13)),

  /// Beside a command of a menu.
  regular(FontSizes.sm, IconSize._(14));

  const KeyGlyphSize(this.text, this.icon);

  final FontSize text;
  final IconSize icon;
}
