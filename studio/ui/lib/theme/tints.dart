import 'package:flutter/widgets.dart';

/// Fills and lines of the log-in page's notices and of its hero that the
/// palette of `context.colors` has no name for (boards `Login`,
/// `Discover…`, `Unlock…`): the same in both brightnesses, as the page is
/// always dark. Named for what they colour.
abstract final class Tints {
  /// A warning card's fill: the trust card, an unlock notice (`#1A1810`).
  static const warnFill = Color(0xFF1A1810);

  /// A warning card's line, and the gateway field while its CA waits for
  /// the check (`#6A5A2A`).
  static const warnLine = Color(0xFF6A5A2A);

  /// A refusal's fill: the unreachable alert, a signed-out notice, between
  /// `ground0` and `badTint` (`#1C1513`).
  static const badFill = Color(0xFF1C1513);

  /// The log-in and offer buttons while busy (`#C9772F`).
  static const emberBusy = Color(0xFFC9772F);

  /// The warm centre of the hero's radial gradient (`#1A1511`).
  static const heroGlow = Color(0xFF1A1511);

  /// The quiet edges of the hero's living tree (`#2A2F33`).
  static const heroEdge = Color(0xFF2A2F33);

  /// A biometric glyph drawn with no colour around it (`#F3A766`, the
  /// palette's `emberSoft` of the dark theme).
  static const glyph = Color(0xFFF3A766);
}
