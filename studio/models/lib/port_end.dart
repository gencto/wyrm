import 'engine_port.dart';

/// One end of a wire: port [port] of block [block] (spec 06 edges:
/// `<node>.<port>`).
final class PortEnd {
  /// The end [port] of [block]; the port's name is decoded once, here,
  /// into [known].
  PortEnd(this.block, this.port)
    : known = EnginePort.fromWire(port),
      param = paramOfPort(port);

  final String block;

  /// The port's name as the definition writes it: any name the catalog or
  /// a custom block gives (spec 06).
  final String port;

  /// [port] as a port the editor treats in its own way (`in`, `out`, …);
  /// null for any other name.
  final EnginePort? known;

  /// The parameter or operand whose input [port] is (`in.<name>`, ADR
  /// 0038 §2); null for any other port.
  final String? param;

  /// The input port of parameter or operand [name]: `in.<name>`.
  static String inputOf(String name) => '$_inMark$name';

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

const _inMark = 'in.';

/// The parameter or operand whose input [port] is (`in.<name>`); null when
/// [port] is no such input. A port's name is read here, once.
String? paramOfPort(String port) =>
    port.startsWith(_inMark) ? port.substring(_inMark.length) : null;
