/// The register area of a modbus point, `cfg.table` (docs/modbus.md).
enum ModbusArea {
  holding('holding'),
  input('input'),
  coil('coil'),
  discrete('discrete');

  const ModbusArea(this.wire);

  /// The area's name in `cfg.table`.
  final String wire;

  /// The area named [name]; null for one this client does not know.
  static ModbusArea? fromWire(String name) =>
      values.where((a) => a.wire == name).firstOrNull;
}
