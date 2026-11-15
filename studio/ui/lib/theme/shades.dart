import 'package:flutter/widgets.dart';

/// Black at a given opacity, for shadows and scrims, the same in both
/// brightnesses (a shadow is darker than any ground) — layer 3 of the theme
/// strategy (see `common.dart`). Named by the opacity in per cent.
abstract final class Shades {
  static const black40 = Color(0x66000000);
  static const black45 = Color(0x73000000);
  static const black50 = Color(0x80000000);
  static const black55 = Color(0x8C000000);
  static const black = Color(0xFF000000);

  /// The ground under a dialog: ground/0 at 60 %.
  static const barrier = Color.fromRGBO(8, 10, 11, 0.6);
}
