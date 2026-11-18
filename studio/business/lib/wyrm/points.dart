import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

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

/// A parameter of a point's `edit` that Studio shows in its own way; a
/// driver's other parameters are shown as they are named and written.
enum StagedParam implements WireName {
  poll(pollParam);

  const StagedParam(this.wire);

  @override
  final String wire;

  static StagedParam? fromWire(String wire) =>
      values.where((p) => p.wire == wire).firstOrNull;
}

/// The name a staged edit shows for an `edit` parameter.
String editFieldName(String param) => switch (StagedParam.fromWire(param)) {
  StagedParam.poll => StagedParam.poll.name,
  null => param,
};

/// The value a staged edit shows for an `edit` parameter.
String editFieldText(String param, Object? value) =>
    switch (StagedParam.fromWire(param)) {
      StagedParam.poll => pollText(value),
      null => value == null || value == '' ? '—' : '$value',
    };
