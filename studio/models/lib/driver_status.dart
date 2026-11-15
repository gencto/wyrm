/// The framework `status` of a connection or a device (ADR 0004), by the
/// names its enum gives; a name not here is a state with no tone of its
/// own (`stopped`, a driver's own).
enum DriverStatus {
  connected('connected'),
  connecting('connecting'),
  unknown('unknown'),
  failed('failed');

  const DriverStatus(this.wire);

  /// The state's name as the driver's enum gives it, in lower case.
  final String wire;

  /// The state named [name] (any case); null for one with no tone.
  static DriverStatus? fromName(String name) {
    final n = name.toLowerCase();
    return values.where((s) => s.wire == n).firstOrNull;
  }
}
