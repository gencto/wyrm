/// Which side of a node a live value of a flow's `watch` or `preview` is
/// on (ADR 0038 §3): a sample that came in, one that went out, or the
/// value of a parameter. [prefix] starts its key in `flowEditor.ports`.
enum PortSide {
  input('in'),
  output('out'),
  param('param');

  const PortSide(this.prefix);

  final String prefix;
}
