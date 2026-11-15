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
