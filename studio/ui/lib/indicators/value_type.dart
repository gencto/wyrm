/// The type of a value (spec 02 `ty`), as a table names it and a tree tags
/// it. The names are the protocol's own (`number`, `bool`), in mono.
enum ValueType {
  null_('null', '·'),
  number('number', '.0'),
  string('string', 'Aa'),
  bool_('bool', '01'),
  enum_('enum', '≡'),
  map('map', '{}'),
  array('array', '{}'),
  binary('binary', '0x'),
  dynamic_('dynamic', '{}');

  const ValueType(this.word, this.tag);

  /// The type's name: `number`.
  final String word;

  /// The tag a point carries beside its name (board *Icons* "Point: add
  /// its type tag").
  final String tag;
}
