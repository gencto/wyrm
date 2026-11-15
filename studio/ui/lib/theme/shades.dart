import 'package:flutter/widgets.dart';

/// Shadow and scrim colours, the same in both brightnesses (a shadow is
/// darker than any ground) — layer 3 of the theme strategy (see
/// `common.dart`). Named for what casts them.
abstract final class Shades {
  /// Under a dialog's card (Account › Security, the step-up, the lock).
  static const dialogShadow = Color(0x80000000);

  /// Under the error dialog's card.
  static const errorDialogShadow = Color(0x8C000000);

  /// Under a trend's tooltip.
  static const tooltipShadow = Color(0x80000000);

  /// Under a floating card: a toast, the block palette, the scope prompt.
  static const popupShadow = Color(0x73000000);

  /// Along the edge of a side drawer (Problems, Review and apply).
  static const drawerShadow = Color(0x66000000);

  /// The ground under a dialog: ground/0 at 60 %.
  static const barrier = Color.fromRGBO(8, 10, 11, 0.6);

  /// An opaque paint that only cuts a mask (`BlendMode.dstOut`); its colour
  /// never shows.
  static const mask = Color(0xFF000000);
}

/// Grounds that stay the same in both brightnesses, outside the palette of
/// `AppColors`. Named for what they fill.
abstract final class FixedGrounds {
  /// The header of an own (`MY`) block on the flow canvas.
  static const flowOwnBlockHeader = Color(0xFF3A2A1C);
}
