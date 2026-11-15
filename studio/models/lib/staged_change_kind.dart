/// What a staged change does to its key, as the first part of its id in
/// the staged table: a value set, a link's parameters replaced. Two
/// changes of one kind on one key are one change (the later one wins).
enum StagedChangeKind {
  set('set'),
  params('params');

  const StagedChangeKind(this.prefix);

  final String prefix;

  /// The id of a change of this kind on the full [key].
  String idOf(String key) => '$prefix:$key';
}
