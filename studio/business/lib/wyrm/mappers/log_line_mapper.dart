import 'package:models/log_line.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The records of a `get_log` answer (one array, or a row per record) as
/// [LogLine]s, in the broker's order (oldest first).
List<LogLine> logLinesOf(List<Value> rows) => [
  for (final r in rows)
    for (final e in switch (r) {
      VArray(:final v) => v,
      _ => [r],
    })
      LogLine(
        time: str(e['time']) ?? '',
        level: str(e['level']) ?? '',
        target: str(e['target']) ?? '',
        message: str(e['message']) ?? text(e) ?? '',
      ),
];

/// What Copy and Save as .log write: one record per line,
/// `<time> <LEVEL> <target> <message>`.
String logText(Iterable<LogLine> lines) => [
  for (final l in lines)
    [
      l.time,
      l.level.toUpperCase(),
      l.target,
      l.message,
    ].where((s) => s.isNotEmpty).join(' '),
].join('\n');

/// How far on each side of the Log toolbar's time a line may be and still
/// be shown (docs/design/specs/errors.md §3, *Open the log*).
const logAroundWindow = Duration(minutes: 2);

final _clock = RegExp(r'^\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*$');

/// The second of the day `hh:mm` or `hh:mm:ss` names; null when [text] is
/// not a time of day.
int? secondOfDay(String text) {
  final m = _clock.firstMatch(text);
  if (m == null) {
    return null;
  }
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final s = int.parse(m.group(3) ?? '0');
  return h > 23 || min > 59 || s > 59 ? null : h * 3600 + min * 60 + s;
}

String _clockText(int second) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(second ~/ 3600)}:${two(second ~/ 60 % 60)}:${two(second % 60)}';
}

/// [text] as the toolbar keeps it, `hh:mm:ss`; null when it is not a time
/// of day.
String? clockOf(String text) => switch (secondOfDay(text)) {
  final s? => _clockText(s),
  null => null,
};

/// The moment [at] on the clock the log rows show (UTC), `hh:mm:ss`: what
/// *Open the log* puts in the toolbar's time for an error that came at
/// [at].
String logClockOf(DateTime at) {
  final t = at.toUtc();
  return _clockText(t.hour * 3600 + t.minute * 60 + t.second);
}

/// The lines of [lines] written within [logAroundWindow] of the time of day
/// [around] (`hh:mm[:ss]`, UTC as the broker writes it), in their order;
/// all of them when [around] is null, empty or not a time. `get_log` takes
/// no time, so this is a filter over the lines Studio holds. The date is
/// not compared: the ring holds the newest lines, and a window across
/// midnight is one window. A line whose time cannot be read is left out.
List<LogLine> linesAround(Iterable<LogLine> lines, String? around) {
  final at = around == null ? null : secondOfDay(around);
  if (at == null) {
    return lines.toList();
  }
  const day = 24 * 3600;
  bool near(DateTime t) {
    final d = (t.hour * 3600 + t.minute * 60 + t.second - at).abs();
    return (d > day ~/ 2 ? day - d : d) <= logAroundWindow.inSeconds;
  }

  return [
    for (final l in lines)
      if (DateTime.tryParse(l.time)?.toUtc() case final t? when near(t)) l,
  ];
}

/// `wyrm-<site>-<yyyymmdd-hhmm>.log`, the name Save as .log proposes.
String logFileName(String site, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'wyrm-$site-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.log';
}
