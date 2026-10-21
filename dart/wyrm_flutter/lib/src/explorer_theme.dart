// Colours and measures of the WYRM explorer (dark theme). Values are
// CSS-style pixels; Flutter logical pixels stand in for them.

import 'package:flutter/painting.dart';

abstract final class WyStyle {
  /// Panels, tab content, popup menus.
  static const panel = Color(0xFF323232);

  /// Tab bar background.
  static const tabBar = Color(0xFF1D1C1C);

  /// Borders, separators, splitters.
  static const line = Color(0xFF424244);

  /// Default text, tree labels, triangles.
  static const text = Color(0xFFBBBBC0);

  /// Accent: active tab, icons, input text.
  static const accent = Color(0xFF2EBED7);

  /// Selected row, menu hover, button hover.
  static const selected = Color(0xFF2D7581);

  /// Disabled menu items, secondary text.
  static const disabled = Color(0xFF5E5E60);

  /// Inputs and buttons.
  static const field = Color(0xFF2B2B2B);

  /// Search placeholder.
  static const placeholder = Color(0xFF666666);

  /// Popup shadow.
  static const shadow = [BoxShadow(color: Color(0x40000000), blurRadius: 8)];

  static const font = 'Helvetica';

  static const rowHeight = 30.0;
  static const treePaddingLeft = 10.0;
  static const treeIndent = 15.0;
  static const tabBarHeight = 40.0;

  static const label = TextStyle(fontFamily: font, fontSize: 11, color: text, height: 16 / 11);
  static const tab = TextStyle(fontFamily: font, fontSize: 12, color: text);
  static const menu = TextStyle(fontFamily: font, fontSize: 13, color: text);
  static const input = TextStyle(fontFamily: 'Arial', fontSize: 11, color: accent);
}
