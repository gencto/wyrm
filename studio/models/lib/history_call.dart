/// The node of `sys/history` a [HistoryCall] is made on.
enum HistoryNode {
  /// `sys/history` itself.
  historian,

  /// The watch group picked.
  group,

  /// The watch of the one point picked.
  watch,
}

/// An action of `sys/history` History calls, by its name on the wire and
/// the node it is made on.
enum HistoryCall {
  addWatchGroup('add_watch_group', HistoryNode.historian),
  addWatchPath('add_watch_path', HistoryNode.group),
  edit('edit', HistoryNode.group),
  purge('purge', HistoryNode.historian),
  remove('remove', HistoryNode.group),
  unsubscribe('unsubscribe', HistoryNode.watch);

  const HistoryCall(this.wire, this.node);

  final String wire;
  final HistoryNode node;
}
