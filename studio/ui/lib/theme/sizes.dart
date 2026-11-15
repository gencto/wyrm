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
}
