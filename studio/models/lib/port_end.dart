import 'engine_port.dart';

/// One end of a wire: port [port] of block [block] (spec 06 edges:
/// `<node>.<port>`).
final class PortEnd {
  /// The end [port] of [block]; the port's name is decoded once, here,
  /// into [known].
  PortEnd(this.block, this.port) : known = EnginePort.fromWire(port);

  final String block;

  /// The port's name as the definition writes it: any name the catalog or
  /// a custom block gives (spec 06).
  final String port;

  /// [port] as a port the editor treats in its own way (`in`, `out`, …);
  /// null for any other name.
  final EnginePort? known;

  /// As a definition's edge writes it: `<block>.<port>`.
  String get wire => '$block.$port';

  @override
  bool operator ==(Object other) =>
      other is PortEnd && other.block == block && other.port == port;

  @override
  int get hashCode => Object.hash(block, port);

  @override
  String toString() => wire;
}
