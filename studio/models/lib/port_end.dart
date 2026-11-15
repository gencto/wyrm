/// One end of a wire: port [port] of block [block] (spec 06 edges:
/// `<node>.<port>`).
final class PortEnd {
  const PortEnd(this.block, this.port);

  final String block;
  final String port;

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
