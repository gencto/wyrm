/// The mark beside a point's value: its quality, or why it has none.
enum PointMark {
  good,
  uncertain,
  bad,

  /// No value read yet.
  none,

  /// The site is offline: the value held is from before.
  stale,

  /// The point is staged to be added and not applied yet.
  notApplied,
}
