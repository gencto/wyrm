import 'package:models/hist_window.dart';

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
