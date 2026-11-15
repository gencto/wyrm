/// Where an `edit` parameter of a point goes in the inspector.
enum PointParamGroup { register, value, poll, write }

/// The parameters of a modbus point's `edit` that the board names
/// (docs/design/specs/explorer.md §4, docs/modbus.md), and the two it
/// shows that the driver has none for ([wordOrder], [precision]); [poll]
/// is the poll rate in seconds.
enum PointParam {
  table('table', PointParamGroup.register),
  addr('addr', PointParamGroup.register),
  dtype('dtype', PointParamGroup.register),
  bit('bit', PointParamGroup.register),
  regs('regs', PointParamGroup.register),
  wordOrder('word_order', PointParamGroup.register),
  unit('unit', PointParamGroup.value),
  scale('scale', PointParamGroup.value),
  offset('offset', PointParamGroup.value),
  precision('precision', PointParamGroup.value),
  poll('poll_s', PointParamGroup.poll),
  writable('writable', PointParamGroup.write),
  writableByMaster('writable_by_master', PointParamGroup.write);

  const PointParam(this.wire, this.group);

  /// The parameter's name in the action.
  final String wire;
  final PointParamGroup group;

  /// The parameter named [name]; null for one the board does not name.
  static PointParam? fromWire(String name) =>
      values.where((p) => p.wire == name).firstOrNull;
}
