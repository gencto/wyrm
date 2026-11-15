import 'package:models/audit_entry.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// One record of `sys/audit` ▸ `tail` (`{t, op, key, sub, status}`;
/// `t` in µs since the epoch, `status` 0 when the call went through).
///
/// `key` and `t` are required: a record without them names nothing. The
/// others are as the admin writes them; a missing `op` or `sub` is empty,
/// a missing `status` is 0.
Decoded<AuditEntry> auditEntryOf(Value r) {
  if (r is! VMap) {
    return const Invalid('audit record', '', 'not a map');
  }
  final key = switch (r.v['key']) {
    VStr(:final v) => v,
    _ => null,
  };
  if (key == null) {
    return const Invalid('audit record', 'key', 'missing');
  }
  final t = switch (r.v['t']) {
    VInt(:final v) => v,
    VFloat(:final v) when v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
  if (t == null) {
    return const Invalid('audit record', 't', 'missing');
  }
  String textOf(String field) => switch (r.v[field]) {
    VStr(:final v) => v,
    _ => '',
  };
  return Valid(
    AuditEntry(
      time: DateTime.fromMicrosecondsSinceEpoch(t, isUtc: true),
      op: textOf('op'),
      key: key,
      who: textOf('sub'),
      status: switch (r.v['status']) {
        VInt(:final v) => v,
        _ => 0,
      },
    ),
  );
}

/// The records of the rows `tail` answered: each row a record or an array
/// of them.
List<Decoded<AuditEntry>> auditEntriesOf(Iterable<Value> rows) => [
  for (final row in rows)
    for (final r in switch (row) {
      VArray(:final v) => v,
      _ => [row],
    })
      auditEntryOf(r),
];
