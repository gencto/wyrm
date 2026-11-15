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
  static const panel = EdgeInsets.symmetric(
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
}
