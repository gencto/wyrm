
/// The rollup windows a trend reads, finest first (spec trend.md §4).
const historySteps = [
  ('1m', Duration(minutes: 1)),
  ('5m', Duration(minutes: 5)),
  ('15m', Duration(minutes: 15)),
  ('1h', Duration(hours: 1)),
  ('6h', Duration(hours: 6)),
  ('1d', Duration(days: 1)),
];

/// Raw rows are read for a span up to this long.
const rawUpTo = Duration(hours: 2);

/// At most this many raw rows per key; a key that answers this many is read
/// again as a rollup.
const rawLimit = 5000;

/// The `window` that draws [span] in at most 300 buckets: the finest of
/// [historySteps] that does, or null (raw rows) for a span up to [rawUpTo]
/// when [raw] is allowed.
String? stepFor(Duration span, {bool raw = true}) {
  if (raw && span <= rawUpTo) {
    return null;
  }
  for (final (name, d) in historySteps) {
    if (span.inMicroseconds / d.inMicroseconds <= 300) {
      return name;
    }
  }
  return historySteps.last.$1;
}

/// The length of [step] (`5m`), or null for `raw` and an unknown one.
Duration? stepDuration(String? step) {
  for (final (name, d) in historySteps) {
    if (name == step) {
      return d;
    }
  }
  return null;
}
