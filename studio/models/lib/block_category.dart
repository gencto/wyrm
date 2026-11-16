/// The palette's sections in order (flow-editor.md §2): where a value
/// comes from, the values, the calculations from the plainest, the logic,
/// text and its codecs, data and tables, time, then what the flow does to
/// the tree. A category the engine adds later comes after these, in the
/// catalog's order.
enum BlockCategory {
  sources('Sources'),
  variables('Variables'),
  math('Math'),
  trigonometry('Trigonometry'),
  statistics('Statistics'),
  logic('Logic'),
  textual('Text'),
  codecs('Codecs'),
  data('Data'),
  tables('Tables'),
  dateAndTime('Date and time'),
  alarms('Alarms'),
  outputs('Outputs'),
  wasm('WASM');

  const BlockCategory(this.wire);

  /// The category as the catalog names it (`node_types` `category`).
  final String wire;

  static final Map<String, BlockCategory> _byWire = {
    for (final c in values) c.wire: c,
  };

  /// The category named [s]; null for one the editor does not know (it
  /// comes after these, in the catalog's order).
  static BlockCategory? fromWire(String s) => _byWire[s];
}
