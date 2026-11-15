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

  /// The height of a log or a table shown inside a card or a dialog.
  static const double logPane = 260;

  /// The width of a dialog that shows a log or a history.
  static const double logDialog = 480;

  /// The height of the log-in and unlock buttons.
  static const double tallButton = 50;

  /// A button beside a boxed field, as tall as the field.
  static const double fieldButton = 46;

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
}
