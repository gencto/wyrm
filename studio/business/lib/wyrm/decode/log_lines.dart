import 'package:models/log_level.dart';
import 'package:models/log_line.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

const _shape = 'log line';

/// The answer of `get_log` (`sys` or `sys/links/<id>`): rows of records
/// `{time, level, target, message}`, each row one record or an array of
/// them, in the broker's order. A record that is a plain text is its
/// message. A record of another shape, or a field that is not a text, is
/// [Invalid] with its field.
Decoded<List<LogLine>> logLinesOf(List<Value> rows) {
  final out = <LogLine>[];
  for (final r in rows) {
    for (final e in switch (r) {
      VArray(:final v) => v,
      _ => [r],
    }) {
      switch (_line(e)) {
        case Valid(:final value):
          out.add(value);
        case final Invalid<LogLine> i:
          return Invalid(i.shape, i.field, i.reason);
      }
    }
  }
  return Valid(out);
}

Decoded<LogLine> _line(Value e) {
  switch (e) {
    case VStr(:final v):
      return Valid(LogLine(message: v));
    case VMap(:final v):
      String? bad;
      String field(String name) => switch (v[name]) {
        null || VNull() => '',
        VStr(:final v) => v,
        _ => (bad ??= name, '').$2,
      };
      final level = field('level');
      final line = LogLine(
        time: field('time'),
        target: field('target'),
        message: field('message'),
      );
      if (bad case final f?) {
        return Invalid(_shape, f, 'not a text');
      }
      final named = level.isEmpty ? null : LogLevel.fromWire(level);
      if (level.isNotEmpty && named == null) {
        return const Invalid(_shape, 'level', 'not a level name');
      }
      return Valid(
        line.copyWith(at: DateTime.tryParse(line.time), level: named),
      );
    default:
      return const Invalid(_shape, '', 'not a record');
  }
}
