import 'package:models/node_info.dart';

/// The values the driver framework publishes on every connection and device
/// (ADR 0004): they describe the node, they are not its points
/// (docs/design/specs/explorer.md §3).
const diagnosticNames = {
  'status',
  'error',
  'requests',
  'errors',
  'timeouts',
  'exceptions',
  'reopens',
  'last_rtt_ms',
  'avg_rtt_ms',
};

/// [n] is one of the framework's diagnostic values, not a point.
bool isDiagnostic(NodeInfo n) =>
    n.type != null && diagnosticNames.contains(n.name);

/// [n] is a point: a value that is not a diagnostic.
bool isPoint(NodeInfo n) => n.type != null && !isDiagnostic(n);

/// The parameter of a point's `edit` that holds its poll rate, in seconds.
const pollParam = 'poll_s';

/// A poll rate as the table shows it: `500 ms`, `1 s`, `2.5 s`.
String pollText(Object? seconds) {
  final s = switch (seconds) {
    final num n => n,
    final String t => num.tryParse(t),
    _ => null,
  };
  if (s == null) {
    return '—';
  }
  if (s < 1) {
    return '${(s * 1000).round()} ms';
  }
  return s == s.roundToDouble() ? '${s.round()} s' : '$s s';
}

/// The name a staged edit shows for an `edit` parameter.
String editFieldName(String param) => param == pollParam ? 'poll' : param;

/// The value a staged edit shows for an `edit` parameter.
String editFieldText(String param, Object? value) => switch (param) {
  pollParam => pollText(value),
  _ when value == null || value == '' => '—',
  _ => '$value',
};
