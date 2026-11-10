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

/// `wyrm-<site>-<yyyymmdd-hhmm>.log`, the name Save as .log proposes.
String logFileName(String site, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'wyrm-$site-${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}.log';
}
