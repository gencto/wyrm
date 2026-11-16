import 'package:flutter/widgets.dart';

/// The spacing scale — layer 3 of the theme strategy (see `common.dart`).
///
/// A 4-point scale, doubling from [sm]. A value off the scale is a smell: the
/// point is that screens built from these line up with each other.
abstract final class AppSpacing {
  /// No space, where a constructor asks for every side.
  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  // The flow editor's gaps off the scale, named for what they part
  // (studio/docs/design/specs/flow-editor.md).

  /// Between the parts of one row: a mark and its label, a block row's
  /// label and value, a field and its unit, a list editor's cells.
  static const double flowRowParts = 6;

  /// Between the lines of a stack: a label and its field, the notes under
  /// the palette, the inspector's foot, a list editor's rows.
  static const double flowLines = 6;

  /// Between chips that wrap: a scope's suggestions, a shortcut's key
  /// combinations.
  static const double flowChips = 6;

  /// Between the key glyphs of a shortcut in the canvas menu.
  static const double flowKeyGlyphs = 1;

  /// Between the key chips of one shortcut in the shortcut card.
  static const double flowKeyChips = 3;

  /// Between a command's name and its keys in the shortcut card.
  static const double flowShortcutRow = 12;

  /// Between the two columns of the shortcut card.
  static const double flowShortcutColumns = 28;

  /// Between a palette block type's tag, name and value.
  static const double flowPaletteRow = 10;

  /// Between the sections of the custom block dialog.
  static const double flowDialogSections = 14;

  /// Between the buttons at the foot of a flow editor dialog.
  static const double flowDialogButtons = 10;

  /// Between the title, field, problem and buttons of the name dialog.
  static const double flowNameDialog = 12;

  /// Between the logo, the path and the actions of the flow editor's top
  /// bar.
  static const double flowTopBar = 18;

  /// Between the state, the buttons and the close of the top bar.
  static const double flowTopBarActions = 10;

  /// Sites' map: the room around it, above it and between its legend and
  /// its nodes.
  static const double map = 18;
}

/// Ready-made gaps, so a layout reads as rhythm rather than arithmetic.
abstract final class Gaps {
  /// Vertical — the common case, since columns dominate these layouts.
  static const Widget xs = SizedBox(height: AppSpacing.xs);
  static const Widget sm = SizedBox(height: AppSpacing.sm);
  static const Widget md = SizedBox(height: AppSpacing.md);
  static const Widget lg = SizedBox(height: AppSpacing.lg);
  static const Widget xl = SizedBox(height: AppSpacing.xl);

  /// The step rhythm of a wizard and a workspace page (boards *Add a link*,
  /// *Studio · Links*), named for what they part.
  ///
  /// Between a line and the caption or the warning under it (a field and
  /// the key it makes, a step's number and its question).
  static const Widget caption = SizedBox(height: 6);

  /// Between a section's title and its content (On which broker, the
  /// checks).
  static const Widget sectionTitle = SizedBox(height: 10);

  /// Before a closing note under a grid of cards.
  static const Widget closingNote = SizedBox(height: 14);

  /// Between the groups of one step (the cards, the name, the rights).
  static const Widget stepGroup = SizedBox(height: 18);

  /// Between a step's question and its content.
  static const Widget stepContent = SizedBox(height: 20);

  /// Between a list's title and note and its first row (a wizard's
  /// answers).
  static const Widget listStart = SizedBox(height: 10);

  /// Between a page's header and its tabs.
  static const Widget pageTabs = SizedBox(height: 22);

  /// Between a page's tabs and what the tab on screen says of itself.
  static const Widget tabNote = SizedBox(height: 18);

  /// Horizontal, for a `Row`.
  static const Widget hXs = SizedBox(width: AppSpacing.xs);
  static const Widget hSm = SizedBox(width: AppSpacing.sm);
  static const Widget hMd = SizedBox(width: AppSpacing.md);
  static const Widget hLg = SizedBox(width: AppSpacing.lg);
  static const Widget hXl = SizedBox(width: AppSpacing.xl);

  /// Under the flow inspector's *Problems* label, above its first problem.
  static const Widget flowInspectorLabel = SizedBox(height: 6);

  /// Above a flow inspector field's editor that has an error under it.
  static const Widget flowInspectorEditorTop = SizedBox(height: 6);

  /// Between a flow inspector field's editor and its link button.
  static const Widget hFlowInspectorButtons = SizedBox(width: 6);

  /// Between a workspace page's header and the table or tabs under it
  /// (Flows, Access).
  static const Widget underHeader = SizedBox(height: 20);

  /// Between a page header and a second button under it (Sites' token).
  static const Widget underButtons = SizedBox(height: 14);

  /// Above Sites' map.
  static const Widget aboveMap = SizedBox(height: AppSpacing.map);
}

/// Padding built from the same scale, and the paddings the canvas repeats,
/// named for what they pad.
abstract final class Insets {
  static const sm = EdgeInsets.all(AppSpacing.sm);
  static const md = EdgeInsets.all(AppSpacing.md);
  static const lg = EdgeInsets.all(AppSpacing.lg);

  /// Screen-edge padding: generous horizontally, tighter vertically.
  static const screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.lg,
  );

  /// Inside a one-line control of a fixed height: a field, a chip, a
  /// search box, a block's header row.
  static const control = EdgeInsets.symmetric(horizontal: 10);

  /// Inside a card or a row of a card list (Account › Security's options
  /// and devices, a found gateway, a notice).
  static const card = EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  /// Inside an alert or a banner that spans its panel.
  static const notice = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// Inside a bordered panel of System: a value's tile, the Log toolbar
  /// (board `System`).
  static const systemPanel = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// Around System's main column, beside the attention panel (board
  /// `System`: 28 at the sides).
  static const systemColumn = EdgeInsets.symmetric(
    horizontal: 28,
    vertical: AppSpacing.lg,
  );

  /// Around an Assistant card: indented past the avatar column (42) and
  /// apart from the next card.
  static const assistantCard = EdgeInsets.only(left: 42, bottom: 12);

  /// An Assistant line under the model's mark: indented past the avatar
  /// column, as [assistantCard] is.
  static const assistantIndent = EdgeInsets.only(left: 42);

  /// The title row of a card with rows under it (a plan, a run): as
  /// [card] at the sides and the top, tighter above the first row.
  static const cardHead = EdgeInsets.fromLTRB(14, 12, 14, 10);

  /// One row of a card (a plan's step, a suggestion's title): as [card]
  /// at the sides, tighter between rows.
  static const cardRow = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  /// The line that closes a card under its rows (a note): tighter under
  /// the last row, as [card] at the bottom.
  static const cardFoot = EdgeInsets.fromLTRB(14, 10, 14, 12);

  /// Inside a warning band in a card (a link's finding, a caution).
  static const band = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  /// Inside a removable chip: the text, then its close button.
  static const chip = EdgeInsets.only(left: AppSpacing.sm, right: 2);

  /// Around a wizard's steps in its left rail (board *Add a link*).
  static const wizardRail = EdgeInsets.fromLTRB(12, 20, 12, 20);

  /// Around the label above a wizard's steps.
  static const wizardRailLabel = EdgeInsets.only(
    left: AppSpacing.sm,
    bottom: 12,
  );

  /// Inside a setting's card above a table (Quarantine's admission
  /// options).
  static const settingCard = EdgeInsets.symmetric(horizontal: 14, vertical: 6);

  /// Around a wizard's answers in its right column.
  static const wizardAnswers = EdgeInsets.all(20);

  /// Around a wizard's step: its question and its content.
  static const wizardStep = EdgeInsets.fromLTRB(30, 28, 30, 30);

  /// Around a wizard's Back and Continue.
  static const wizardFoot = EdgeInsets.symmetric(horizontal: 30, vertical: 14);

  /// Inside a pill that filters a list (a category of the official list).
  static const filterPill = EdgeInsets.symmetric(horizontal: 14);

  /// Around a workspace page's header, tabs and table (board *Studio ·
  /// Links*: 28 around, 40 under the table).
  static const workspacePage = EdgeInsets.fromLTRB(28, 28, 28, 40);

  /// Inside a card of the official list (board *Add a link · O1*).
  static const catalogCard = EdgeInsets.all(14);

  /// Inside the short tag of a card of the official list (`MB`).
  static const catalogTag = EdgeInsets.symmetric(horizontal: 5, vertical: 2);

  /// Inside a chip of a card of the official list (`built in`, the
  /// official mark).
  static const catalogChip = EdgeInsets.symmetric(horizontal: 6, vertical: 2);

  /// Inside a step of a wizard's rail.
  static const railStep = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: 12,
  );

  /// Inside a row of a package's checks.
  static const checkRow = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  /// Inside an action card of an inspector.
  static const actionCard = EdgeInsets.symmetric(horizontal: 10, vertical: 10);

  /// Around an inspector's header (its eyebrow, title, pill and key).
  static const inspectorHead = EdgeInsets.fromLTRB(20, 22, 20, AppSpacing.md);

  /// Around an inspector's facts.
  static const inspectorFacts = EdgeInsets.all(20);

  /// Around an inspector's groups of actions and its form.
  static const inspectorBody = EdgeInsets.fromLTRB(20, 18, 20, 20);

  /// Above the label of an inspector's group of actions.
  static const inspectorGroup = EdgeInsets.only(top: 6);

  /// Around the label of an inspector's form.
  static const inspectorForm = EdgeInsets.symmetric(vertical: 6);

  /// Inside an inspector's boxed note at the bottom.
  static const inspectorFooter = EdgeInsets.all(14);

  /// Around a small text button beside chips (`+ prefix`).
  static const textLink = EdgeInsets.symmetric(horizontal: 6, vertical: 3);

  // The flow editor (studio/docs/design/specs/flow-editor.md).

  /// Around the block palette's search box.
  static const flowPaletteSearch = EdgeInsets.all(10);

  /// Around the block palette's list of entries.
  static const flowPaletteList = EdgeInsets.fromLTRB(6, 0, 6, 12);

  /// Inside the notes under the block palette.
  static const flowPaletteNotes = EdgeInsets.fromLTRB(12, 10, 12, 14);

  /// Inside a group header of the block palette: its chevron and name.
  static const flowPaletteGroup = EdgeInsets.symmetric(horizontal: 6);

  /// Inside a point or an action row of the palette's Tree tab.
  static const flowPaletteTreeRow = EdgeInsets.fromLTRB(
    22,
    0,
    AppSpacing.sm,
    0,
  );

  /// Inside a dialog of the flow editor (a custom block, a name).
  static const flowDialog = EdgeInsets.all(22);

  /// Inside the head of the flow inspector: its kind, title and note.
  static const flowInspectorHead = EdgeInsets.fromLTRB(
    18,
    AppSpacing.md,
    18,
    12,
  );

  /// Around the name field above the flow inspector's head.
  static const flowInspectorName = EdgeInsets.fromLTRB(
    18,
    AppSpacing.md,
    18,
    0,
  );

  /// Around the flow inspector's list of fields.
  static const flowInspectorList = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 10,
  );

  /// Under a link button at the top of the flow inspector's list.
  static const flowInspectorLink = EdgeInsets.only(bottom: 6);

  /// Around the label of the flow inspector's first group of fields.
  static const flowInspectorFirstGroup = EdgeInsets.only(top: 2, bottom: 2);

  /// Around the label of a later group of fields: apart from the one above.
  static const flowInspectorGroup = EdgeInsets.only(top: 14, bottom: 2);

  /// Inside the foot of the flow inspector.
  static const flowInspectorFoot = EdgeInsets.fromLTRB(18, 14, 18, 18);

  /// Around a problem of the flow summary in the inspector.
  static const flowInspectorProblem = EdgeInsets.symmetric(vertical: 6);

  /// Above a problem's dot, so it sits on the first line of its text.
  static const flowInspectorProblemDot = EdgeInsets.only(top: 6);

  /// Around a list editor that takes the inspector's width under its label.
  static const flowInspectorWideEditor = EdgeInsets.fromLTRB(
    0,
    0,
    6,
    AppSpacing.sm,
  );

  /// Inside an output field of the inspector: its value and its targets.
  static const flowInspectorOutput = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: AppSpacing.xs,
  );

  /// Around a run button of the inspector that says why it is off.
  static const flowInspectorRunWhy = EdgeInsets.symmetric(vertical: 6);

  /// Inside an inspector text field that holds several lines.
  static const flowTextEditorLines = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );

  /// Inside a suggest field of the inspector, before its menu button.
  static const flowSuggestField = EdgeInsets.only(left: 10);

  /// Inside a kind or tag chip in a flow block's header.
  static const flowBlockChip = EdgeInsets.symmetric(
    horizontal: AppSpacing.xs,
    vertical: 1,
  );

  /// Inside a row of a flow block: its label, value and link row.
  static const flowBlockRow = EdgeInsets.symmetric(horizontal: 12);

  /// Around the − / + row under a flow block's fields.
  static const flowBlockToolsMargin = EdgeInsets.fromLTRB(
    12,
    AppSpacing.xs,
    12,
    0,
  );

  /// Above the − / + buttons, under the line that opens their row.
  static const flowBlockTools = EdgeInsets.only(top: 6);

  /// Inside a command input of a flow block, drawn as a button.
  static const flowBlockCommand = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: 2,
  );

  /// Around the icon of a flow block row's action button.
  static const flowBlockRowAction = EdgeInsets.all(3);

  /// How far the flow canvas pans past its edges.
  static const flowCanvasBoundary = EdgeInsets.all(200);

  /// Inside the legend over the flow canvas.
  static const flowLegend = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: AppSpacing.sm,
  );

  /// Above and below the commands of the flow canvas menu.
  static const flowMenu = EdgeInsets.symmetric(vertical: 6);

  /// Inside the title row of the flow canvas menu.
  static const flowMenuTitle = EdgeInsets.fromLTRB(14, 6, 14, 6);

  /// Inside a command of the flow canvas menu.
  static const flowMenuItem = EdgeInsets.symmetric(horizontal: 14);

  /// Above the menu's `Fields ▸` checklist, so it opens beside its item.
  static const flowMenuFields = EdgeInsets.only(top: 40);

  /// Inside the title of the `Fields ▸` checklist.
  static const flowMenuFieldsTitle = EdgeInsets.fromLTRB(12, 6, 12, 6);

  /// Inside a field of the `Fields ▸` checklist.
  static const flowMenuField = EdgeInsets.symmetric(horizontal: 12);

  /// Inside the card of the scope prompt.
  static const flowScopePrompt = EdgeInsets.all(12);

  /// Inside a suggested scope's chip of the scope prompt.
  static const flowScopeChip = EdgeInsets.symmetric(horizontal: 6, vertical: 3);

  /// Inside a key chip of the shortcut card.
  static const flowKeyChip = EdgeInsets.symmetric(horizontal: 6);

  /// Above a command's name in the shortcut card, level with its keys.
  static const flowShortcutLabel = EdgeInsets.only(top: 3);

  /// Under a group's title in the shortcut card.
  static const flowShortcutGroupTitle = EdgeInsets.only(bottom: 6);

  /// Inside the head of the shortcut card: its title and close button.
  static const flowShortcutHead = EdgeInsets.fromLTRB(
    18,
    10,
    AppSpacing.sm,
    10,
  );

  /// Around the groups of the shortcut card.
  static const flowShortcutBody = EdgeInsets.fromLTRB(
    18,
    14,
    18,
    AppSpacing.md,
  );

  /// Inside the note at the foot of the shortcut card.
  static const flowShortcutFoot = EdgeInsets.fromLTRB(18, 10, 18, 12);

  /// Above and below the flow editor's top bar.
  static const flowTopBar = EdgeInsets.symmetric(vertical: 6);

  /// The scrolling body of a workspace page with a header (Flows, Access,
  /// Sites): roomy at the sides and the top, more below the last row.
  static const workspace = EdgeInsets.fromLTRB(28, 28, 28, 40);

  /// Around Sites' map, inside its card.
  static const map = EdgeInsets.all(AppSpacing.map);

  /// Inside a banner across a page (Sites' connections waiting).
  static const waiting = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  // ---- the log-in page, the unlock, the lock and the step-up ----

  /// Around the log-in form, in its panel (login.md §1: 40 × 32).
  static const logInForm = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: 40,
  );

  /// Around the welcome while the tree opens.
  static const welcome = EdgeInsets.symmetric(vertical: 40);

  /// Around the hero's content (login.md §2: 40 × 48).
  static const hero = EdgeInsets.fromLTRB(48, 40, 48, 40);

  /// Beside the hero's logo mark.
  static const heroMark = EdgeInsets.only(right: 1);

  /// Above the trust card or the panel of found gateways, under the
  /// gateway field's status line.
  static const underGateway = EdgeInsets.only(top: 12);

  /// Above a footer's text, under its rule (the log-in form, the unlock).
  static const footer = EdgeInsets.only(top: 14);

  /// Beside the label of a button of a fixed height (the alert's buttons,
  /// *Find on this network*, *Probe*).
  static const button = EdgeInsets.symmetric(horizontal: 14);

  /// Inside a small field of a row of fields (*Probe a range*).
  static const smallField = EdgeInsets.symmetric(horizontal: 12);

  /// Inside the box of the CA code on the trust card.
  static const caCode = EdgeInsets.all(12);

  /// Inside the panel of found gateways, and the step-up's device row.
  static const panelBox = EdgeInsets.all(14);

  /// Above a bullet's dot, to sit on the first line of its text.
  static const bulletDot = EdgeInsets.only(top: 7);

  /// Above *Probe a range instead*, under the reasons.
  static const probeRange = EdgeInsets.only(top: 10);

  /// Inside a tag of a found gateway.
  static const foundTag = EdgeInsets.symmetric(horizontal: 7, vertical: 1);

  /// Above and below the round unlock button and its lines.
  static const unlockButton = EdgeInsets.symmetric(vertical: 6);

  /// Inside the account card of the unlock.
  static const accountCard = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: 14,
  );

  /// The step-up dialog: its head, the box of changes, a row under them
  /// (the password, the device), the gap above its foot and the foot.
  static const dialogHead = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    22,
    AppSpacing.lg,
    6,
  );
  static const dialogList = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: 10,
  );
  static const dialogRow = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    6,
    AppSpacing.lg,
    AppSpacing.none,
  );
  static const dialogFootGap = EdgeInsets.only(top: 12);
  static const dialogFoot = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: 18,
  );

  /// Inside the level badge of a step-up change.
  static const levelBadge = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: 2,
  );
}
