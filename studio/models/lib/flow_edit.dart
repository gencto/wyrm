/// An edit of the flow editor's canvas that the store carries out (spec
/// §13): from a key or from the canvas menu. The canvas and the page
/// answer the rest (selection, zoom, the shortcut card) themselves.
enum FlowEdit {
  copy,
  cut,
  paste,
  duplicate,
  delete,
  undo,
  redo,

  /// Esc: the value viewer closes first, then the selection is cleared.
  escape,
  tidy,

  /// The one selected instance of a custom block opens to its inside.
  editCustomBlock,
}
