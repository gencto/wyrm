/// The type of a node of a flow definition (spec 06 `nodes.<id>.type`),
/// read once from its wire name by [BlockType.fromWire] and typed from
/// there on: an engine type ([EngineType], with the [KnownBlock] the editor
/// knows by name), an instance of a custom block ([CustomType],
/// `block:<name>`, spec 06 0.2.24) or one of the two boundary blocks the
/// editor draws inside a custom block ([BoundaryType], `block~inputs` /
/// `block~outputs`, never sent to the engine).
///
/// Two types are equal when their wire names are.
sealed class BlockType {
  const BlockType();

  /// The prefix of an instance's type: `block:<name>`.
  static const customPrefix = 'block:';

  /// The type named [wire]. Only the decoders of
  /// `business/lib/wyrm/decode/` (a definition, the catalog, the clipboard)
  /// call it: past them a type is never a string again.
  static BlockType fromWire(String wire) {
    if (BoundarySide.fromWire(wire) case final side?) {
      return BoundaryType(side);
    }
    if (wire.startsWith(customPrefix)) {
      return CustomType(wire.substring(customPrefix.length));
    }
    return EngineType._(wire, KnownBlock.fromWire(wire));
  }

  /// The name the definition writes.
  String get wire;

  /// The engine type the editor knows by name; null for any other type, a
  /// custom block and a boundary block.
  KnownBlock? get known => null;

  @override
  String toString() => wire;
}

/// A type of the flow engine's catalog (`node_types`).
final class EngineType extends BlockType {
  /// A type the editor knows by name.
  const EngineType.known(KnownBlock this.known) : _name = null;

  const EngineType._(String name, this.known) : _name = name;

  /// The name as it came, for a type the editor does not know.
  final String? _name;

  @override
  String get wire => _name ?? known?.wire ?? '';

  @override
  final KnownBlock? known;

  @override
  bool operator ==(Object other) => other is EngineType && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// An instance of custom block [name] (`block:<name>`).
final class CustomType extends BlockType {
  const CustomType(this.name);

  /// The block's name in the definition's `blocks`.
  final String name;

  @override
  String get wire => '${BlockType.customPrefix}$name';

  @override
  bool operator ==(Object other) => other is CustomType && other.name == name;

  @override
  int get hashCode => Object.hash(CustomType, name);
}

/// One of the two blocks the inside of a custom block shows beside its
/// nodes: its inputs (one output port each) or its outputs (one input port
/// each). The editor's own: the engine never sees them.
final class BoundaryType extends BlockType {
  const BoundaryType(this.side);

  static const inputs = BoundaryType(BoundarySide.inputs);
  static const outputs = BoundaryType(BoundarySide.outputs);

  final BoundarySide side;

  @override
  String get wire => side.wire;

  @override
  bool operator ==(Object other) => other is BoundaryType && other.side == side;

  @override
  int get hashCode => Object.hash(BoundaryType, side);
}

/// Which boundary block of a custom block's inside.
enum BoundarySide {
  inputs('block~inputs'),
  outputs('block~outputs');

  const BoundarySide(this.wire);

  final String wire;

  static BoundarySide? fromWire(String s) => switch (s) {
    _ when s == inputs.wire => inputs,
    _ when s == outputs.wire => outputs,
    _ => null,
  };
}

/// The engine types the Studio code tests for, keys a table on or creates
/// (docs/flow-blocks.md). Any other engine type is an [EngineType] with no
/// [BlockType.known]: it is drawn from its catalog entry alone.
enum KnownBlock {
  // Sources: what reads the tree.
  subscribe('subscribe'),
  liveliness('liveliness'),
  loadValue('load_value'),
  listChildren('list_children'),
  loadHistory('load_history'),
  getNode('get_node'),
  timer('timer'),
  history('history'),
  dql('dql'),

  // Variables.
  const_('const'),
  number('number'),
  string('string'),
  bool_('bool'),
  constant('constant'),

  // Outputs: what acts on the tree.
  set('set'),
  invoke('invoke'),
  publish('publish'),

  // Logic and data the editor draws in its own way.
  scale('scale'),
  latch('latch'),
  stopwatch('stopwatch'),
  delay('delay'),
  deadband('deadband'),
  alarm('alarm'),
  if_('if'),
  case_('case'),
  router('router'),
  concat('concat'),
  hub('hub'),
  stats('stats'),
  split('split'),
  replace('replace'),
  throttle('throttle'),
  debounce('debounce'),
  jsonParse('json_parse'),
  wasm('wasm'),

  // Date and time (ADR 0044 §3).
  now('now'),
  dateTime('date_time'),
  dateParse('date_parse'),
  dateFormat('date_format'),
  dateMath('date_math'),
  dateRange('date_range'),

  // Tables (ADR 0044 §2).
  table('table'),
  tableFromCsv('table_from_csv'),
  tableFromJson('table_from_json'),
  tablePage('table_page'),
  tableRollup('table_rollup'),
  tableMapColumns('table_map_columns'),
  tableGroupBy('table_group_by'),
  tableRecorder('table_recorder'),
  tableFilter('table_filter'),
  tableRemoveRows('table_remove_rows'),
  tableEditRows('table_edit_rows');

  const KnownBlock(this.wire);

  /// The engine's name of the type.
  final String wire;

  /// This type as a [BlockType].
  BlockType get type => EngineType.known(this);

  static final Map<String, KnownBlock> _byWire = {
    for (final k in values) k.wire: k,
  };

  static KnownBlock? fromWire(String s) => _byWire[s];
}
