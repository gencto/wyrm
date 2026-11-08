import 'package:flutter/widgets.dart';

/// Corner-radius tokens (board *Design system* §04) — layer 3 of the theme
/// strategy (see `common.dart`).
abstract final class AppRadii {
  /// A chip, a tag.
  static const double chip = 4;

  /// A segment inside a control; an input row.
  static const double segment = 6;

  /// A control that groups segments.
  static const double control = 8;

  static const double input = 8;
  static const double button = 8;

  /// A card, a flow block.
  static const double card = 10;

  /// A panel or a large card.
  static const double panel = 12;

  /// A status pill.
  static const double pill = 999;
}

/// The same tokens as ready `BorderRadius`, so a widget does not restate
/// `BorderRadius.circular` at every call.
abstract final class Radii {
  static const chip = BorderRadius.all(Radius.circular(AppRadii.chip));
  static const segment = BorderRadius.all(Radius.circular(AppRadii.segment));
  static const control = BorderRadius.all(Radius.circular(AppRadii.control));
  static const input = BorderRadius.all(Radius.circular(AppRadii.input));
  static const button = BorderRadius.all(Radius.circular(AppRadii.button));
  static const card = BorderRadius.all(Radius.circular(AppRadii.card));
  static const panel = BorderRadius.all(Radius.circular(AppRadii.panel));
  static const pill = BorderRadius.all(Radius.circular(AppRadii.pill));
}
