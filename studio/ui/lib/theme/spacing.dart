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
}
