import 'package:business/wyrm/history_steps.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';
import 'package:models/hist_point.dart';
import 'package:models/hist_window.dart';
import 'package:ui/charts/trend.dart';

/// What the three trends of Studio (History, Explorer, System) share on the
/// connector side (spec trend.md §5): times in the viewer's zone and
/// language, rows as samples, and the words for what a plot draws.

String _two(int n) => n.toString().padLeft(2, '0');

/// Times in local time, weekday and month names from the locale's words.
TrendFormat trendFormat() {
  final days = S.current.trendWeekdays.split(',');
  final months = S.current.trendMonths.split(',');
  String wd(DateTime t) => days[(t.weekday - 1) % days.length];
  return TrendFormat(
    locale: '${S.current.trendWeekdays} ${DateTime.now().timeZoneOffset}',
    clock: (t) {
      final l = t.toLocal();
      return '${_two(l.hour)}:${_two(l.minute)}';
    },
    clockSeconds: (t) {
      final l = t.toLocal();
      return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
    },
    day: (t) {
      final l = t.toLocal();
      return '${wd(l)} ${l.day} ${months[(l.month - 1) % months.length]}';
    },
    weekday: (t) => wd(t.toLocal()),
  );
}

/// `15 min avg`, `1 h avg`, `raw`.
String rollupText(String? step) {
  final s = S.current;
  final d = stepDuration(step);
  if (d == null) {
    return s.trendRaw;
  }
  final name = d.inDays >= 1 && d.inHours % 24 == 0
      ? s.trendStepDays('${d.inDays}')
      : d.inHours >= 1 && d.inMinutes % 60 == 0
      ? s.trendStepHours('${d.inHours}')
      : s.trendStepMinutes('${d.inMinutes}');
  return s.trendAvg(name);
}

TrendQuality _quality(String? q) => switch (q) {
  'bad' => .bad,
  'uncertain' => .uncertain,
  _ => .good,
};

/// [rows] as samples, with the bucket's min and max from [low] and [high]
/// (same times) when they were read.
List<TrendSample> trendSamples(
  IList<HistPoint> rows, {
  IList<HistPoint>? low,
  IList<HistPoint>? high,
}) {
  final lo = {
    for (final p in low ?? const IListConst(<HistPoint>[])) p.time: p.value,
  };
  final hi = {
    for (final p in high ?? const IListConst(<HistPoint>[])) p.time: p.value,
  };
  return [
    for (final p in rows)
      TrendSample(
        p.time.microsecondsSinceEpoch,
        p.value?.toDouble(),
        q: _quality(p.quality),
        lo: lo[p.time]?.toDouble(),
        hi: hi[p.time]?.toDouble(),
      ),
  ];
}

/// The decimals to write values of [rows] with: the point's `precision`
/// when known, else 0 for whole numbers and 1 otherwise.
int trendDecimals(Iterable<HistPoint> rows, {Object? precision}) {
  if (precision case final num p) {
    return p.toInt().clamp(0, 6);
  }
  for (final r in rows) {
    final v = r.value;
    if (v != null && v != v.roundToDouble()) {
      return 1;
    }
  }
  return 0;
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
