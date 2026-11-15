import 'package:models/audit_line.dart';
import 'package:models/grant_source.dart';
import 'package:models/role_grant.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// The rows of an answer that lists records: a row is an array of records
/// or one record.
Iterable<Value> recordsOf(List<Value> rows) sync* {
  for (final r in rows) {
    switch (r) {
      case VArray(:final v):
        yield* v;
      default:
        yield r;
    }
  }
}

/// One text field of a record; empty when it is missing.
Decoded<String> _text(Map<String, Value> m, String shape, String field) =>
    switch (m[field]) {
      null || VNull() => const Valid(''),
      VStr(:final v) => Valid(v),
      _ => Invalid(shape, field, 'not a text'),
    };

/// One grant of `sys ▸ get_permissions` (wyrm-admin `perm_row`): its
/// subject, key pattern, level and source, each a text.
Decoded<RoleGrant> roleGrantOf(Value v) {
  const shape = 'grant';
  final m = switch (v) {
    VMap(:final v) => v,
    _ => null,
  };
  if (m == null) {
    return const Invalid(shape, '', 'not a map');
  }
  final fields = [
    for (final f in ['subject', 'path', 'level', 'source']) _text(m, shape, f),
  ];
  if (fields.whereType<Invalid<String>>().firstOrNull case final bad?) {
    return Invalid(shape, bad.field, bad.reason);
  }
  final [subject, path, level, source] = [
    for (final f in fields) (f as Valid<String>).value,
  ];
  return Valid(
    RoleGrant(
      subject: subject,
      path: path,
      level: level,
      source: GrantSource.fromWire(source),
    ),
  );
}

/// One record of `sys/audit ▸ tail`: its time (`time` or `t`), who
/// (`who`, `by` or `subject`), what (`op` or `event`, `key` or `target`,
/// `action`) and the result (`result` or `status`), each as written (a
/// number as its digits).
Decoded<AuditLine> auditLineOf(Value v) {
  const shape = 'audit record';
  final m = switch (v) {
    VMap(:final v) => v,
    _ => null,
  };
  if (m == null) {
    return const Invalid(shape, '', 'not a map');
  }
  // A field written as a text or a number (wyrm-admin writes `t` and
  // `status` as numbers), as it reads.
  String? first(List<String> names) {
    for (final n in names) {
      switch (m[n]) {
        case VStr(:final v) when v.isNotEmpty:
          return v;
        case VInt(:final v):
          return '$v';
        case VFloat(:final v):
          return '$v';
        default:
          break;
      }
    }
    return null;
  }

  return Valid(
    AuditLine(
      time: first(['time', 't']) ?? '',
      who: first(['who', 'by', 'subject']) ?? '',
      what: [
        first(['op', 'event']),
        first(['key', 'target']),
        first(['action']),
      ].nonNulls.join(' '),
      result: first(['result', 'status']) ?? '',
    ),
  );
}
