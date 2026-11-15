/// The type the flow engine gives a port (spec 06 `port_types`, ADR 0038
/// §2): a wire fits when both ends have one type or either is [any].
enum PortType {
  number('number'),
  boolean('bool'),
  map('map'),
  any('any');

  const PortType(this.wire);

  /// The engine's name of the type.
  final String wire;

  static PortType? fromWire(String s) => switch (s) {
    _ when s == number.wire => number,
    _ when s == boolean.wire => boolean,
    _ when s == map.wire => map,
    _ when s == any.wire => any,
    _ => null,
  };

  /// Whether a wire from a port of this type may feed one of [to].
  bool fits(PortType to) => this == to || this == any || to == any;
}
