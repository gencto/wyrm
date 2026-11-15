/// Sizes of components the canvas repeats — layer 3 of the theme strategy
/// (see `common.dart`). A size used once belongs to its widget as a named
/// constant; a size two widgets share is here.
abstract final class AppSizes {
  /// A menu's width (the account menu, a node's menu).
  static const double menu = 300;

  /// The height of a log or a table shown inside a card or a dialog.
  static const double logPane = 260;

  /// The width of a dialog that shows a log or a history.
  static const double logDialog = 480;

  /// The height of the log-in and unlock buttons.
  static const double tallButton = 50;

  /// A tile of the gallery page.
  static const double galleryTile = 380;
}
