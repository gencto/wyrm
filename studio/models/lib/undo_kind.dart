/// The edits of the flow editor that merge into one step of the history
/// when they come in a row.
enum UndoKind {
  /// Blocks moved by the arrow keys.
  nudge,

  /// A parameter typed into.
  param,

  /// An operand constant typed into.
  operand,
}
