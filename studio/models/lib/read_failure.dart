/// What of a node could not be read (docs/design/specs/errors.md §4): its
/// value, its list of children, its `~meta`.
enum ReadFailure {
  value,
  list,
  meta,
}
