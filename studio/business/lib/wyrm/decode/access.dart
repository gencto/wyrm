import 'package:models/audit_line.dart';
import 'package:models/grant_level.dart';
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
  final from = GrantSource.fromWire(source);
  if (from == null) {
    // the source decides how `level` reads: not known here, not read
    return const Invalid(shape, 'source', 'not a source');
  }
  // A rule of the router's ACL words its messages and flows, no level; a
  // role's or a link's grant names a level, and a name that is none
  // refuses the row: it is never read as a level.
  final typed = switch (from) {
    GrantSource.acl => GrantLevel.rule(level),
    GrantSource.gateway || GrantSource.link => switch (Perm.fromWire(level)) {
      final p? => GrantLevel.perm(p),
      null => null,
    },
  };
  if (typed == null) {
    return const Invalid(shape, 'level', 'not a level');
  }
  return Valid(
    RoleGrant(subject: subject, path: path, level: typed, source: from),
  );
}

/// One record of `sys/audit ▸ tail`, as wyrm-admin writes it (`t`, `sub`,
/// `op`, `key`, `status`) or with the other names a record may use: its
/// time (`t` or `time`), who (`sub`, `who`, `by` or `subject`), what (`op`
/// or `event`, `key` or `target`, `action`) and the result (`result` or
/// `status`), each as written (a number as its digits).
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
      time: first(['t', 'time']) ?? '',
      who: first(['sub', 'who', 'by', 'subject']) ?? '',
      what: [
        first(['op', 'event']),
        first(['key', 'target']),
        first(['action']),
      ].nonNulls.join(' '),
      result: first(['result', 'status']) ?? '',
    ),
  );
}
