/// A button of Explorer's header, points toolbar or selection bar that
/// starts something on the node on screen (docs/design/specs/explorer.md):
/// what the business side runs for it.
enum ExplorerCommand {
  /// A device's Ping, beside Actions ▾.
  ping,

  /// Add point: its form in the inspector.
  addPoint,

  /// Import: the form of the node's import action.
  importPoints,

  /// Remove…: a `remove` of each checked row staged.
  removeChecked,
}
