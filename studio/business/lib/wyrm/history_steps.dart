import 'package:models/hist_window.dart';

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

/// The window the user chose on a trend over [rangeStart]…[rangeEnd] (µs),
/// as the store keeps it: null for the whole range, an open end while it
/// reaches the range's end (it follows now).
HistWindow? trendWindow(int start, int end, int rangeStart, int rangeEnd) {
  const slack = 1000000; // 1 s
  final toEnd = end >= rangeEnd - slack;
  if (start <= rangeStart + slack && toEnd) {
    return null;
  }
  return HistWindow(
    span: Duration(microseconds: end - start),
    end: toEnd ? null : DateTime.fromMicrosecondsSinceEpoch(end, isUtc: true),
  );
}

/// The end of a trend's range (µs): the latest of when it was read
/// ([readAt], now when never) and the [newest] rows since (the range's last
/// samples, the window's own read), so the range stays put between
/// dispatches and still moves with new samples.
int trendRangeEnd(DateTime? readAt, Iterable<DateTime?> newest) {
  var end = readAt ?? DateTime.now().toUtc();
  for (final t in newest) {
    if (t != null && t.isAfter(end)) {
      end = t;
    }
  }
  return end.microsecondsSinceEpoch;
}
