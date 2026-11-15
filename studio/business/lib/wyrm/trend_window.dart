import 'package:models/hist_point.dart';
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

/// The finer rows read for [from]…[to] (µs) cover the window
/// [start]…[end]: they start at most a minute after it and, unless the
/// window [follows] now (its rows grow with new samples), end at most a
/// minute before it.
bool detailCovers({
  required int from,
  required int to,
  required int start,
  required int end,
  required bool follows,
}) {
  const slack = 60 * 1000000;
  return from <= start + slack && (follows || to >= end - slack);
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

/// The decimals to write values of [rows] with: the point's [precision]
/// when known, else 0 for whole numbers and 1 otherwise.
int decimalsOf(Iterable<HistPoint> rows, {int? precision}) {
  if (precision != null) {
    return precision.clamp(0, 6);
  }
  for (final r in rows) {
    final v = r.value;
    if (v != null && v != v.roundToDouble()) {
      return 1;
    }
  }
  return 0;
}

/// A span of a trend's time axis, in µs since the epoch.
final class TrendSpan {
  const TrendSpan(this.start, this.end);

  final int start;
  final int end;
}
