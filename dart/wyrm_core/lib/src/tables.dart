// Code tables from spec/tables.json. `test/tables_test.dart` checks that
// every enum here equals its table: same codes, same names.

/// Value quality (spec 03, key 1).
enum Quality {
  good(0, 'good'),
  uncertain(1, 'uncertain'),
  bad(2, 'bad');

  final int code;
  final String wireName;
  const Quality(this.code, this.wireName);

  static Quality? fromCode(int c) => _byCode(values, c, (v) => v.code);
  static Quality? fromName(String n) => _byName(values, n, (v) => v.wireName);
}

/// Permission level (spec 04), ordered `none < list < … < config`.
enum Perm {
  none(0, 'none'),
  list(1, 'list'),
  read(2, 'read'),
  write(3, 'write'),
  config(4, 'config');

  final int code;
  final String wireName;
  const Perm(this.code, this.wireName);

  static Perm? fromCode(int c) => _byCode(values, c, (v) => v.code);
  static Perm? fromName(String n) => _byName(values, n, (v) => v.wireName);
}

/// `~meta.writable` (spec 02, key 4).
enum Writable {
  never(0, 'never'),
  config(1, 'config'),
  write(2, 'write');

  final int code;
  final String wireName;
  const Writable(this.code, this.wireName);

  static Writable? fromCode(int c) => _byCode(values, c, (v) => v.code);
}

/// Value type code (spec 02, key 1).
enum TypeCode {
  null_(0, 'null'),
  number(1, 'number'),
  string(2, 'string'),
  bool_(3, 'bool'),
  enum_(4, 'enum'),
  map(5, 'map'),
  array(6, 'array'),
  binary(7, 'binary'),
  dynamic_(8, 'dynamic');

  final int code;
  final String wireName;
  const TypeCode(this.code, this.wireName);

  static TypeCode? fromCode(int c) => _byCode(values, c, (v) => v.code);
}

/// Status codes (spec 04).
enum Status {
  ok(0x00, 'ok'),
  initializing(0x01, 'initializing'),
  refreshed(0x02, 'refreshed'),
  notAvailable(0x08, 'not_available'),
  closed(0x10, 'closed'),
  disconnected(0x20, 'disconnected'),
  permissionDenied(0x21, 'permission_denied'),
  invalidMessage(0x22, 'invalid_message'),
  invalidParameter(0x23, 'invalid_parameter'),
  busy(0x24, 'busy'),
  internalError(0x25, 'internal_error'),
  notSupported(0x26, 'not_supported'),
  notFound(0x27, 'not_found'),
  timeout(0x28, 'timeout'),
  outOfRange(0x29, 'out_of_range'),
  rateLimited(0x2A, 'rate_limited'),
  resourceExhausted(0x2B, 'resource_exhausted');

  final int code;
  final String wireName;
  const Status(this.code, this.wireName);

  static Status? fromCode(int c) => _byCode(values, c, (v) => v.code);
  StatusGroup get group => StatusGroup.of(code);
}

/// `< 0x10` success/progress, `0x10–0x1F` closing, `≥ 0x20` error.
enum StatusGroup {
  progress,
  closed,
  error;

  static StatusGroup of(int code) => code < 0x10
      ? StatusGroup.progress
      : code < 0x20
          ? StatusGroup.closed
          : StatusGroup.error;
}

/// User-defined status codes (spec 04).
const int userStatusFirst = 0x40;
const int userStatusLast = 0x4F;

/// A status code on the wire: known, user-defined or unknown.
class StatusCode {
  final int code;
  const StatusCode(this.code);
  StatusCode.of(Status s) : code = s.code;

  Status? get known => Status.fromCode(code);
  bool get isUser => code >= userStatusFirst && code <= userStatusLast;
  StatusGroup get group => StatusGroup.of(code);
  bool get isError => group == StatusGroup.error;
  String get name => known?.wireName ?? (isUser ? 'user_$code' : 'unknown_$code');

  @override
  bool operator ==(Object other) => other is StatusCode && other.code == code;
  @override
  int get hashCode => code;
  @override
  String toString() => name;
}

/// Interned profile codes (`is_codes`).
const Map<int, String> isCodes = {
  0: 'wy:node',
  1: 'wy:folder',
  2: 'wy:number',
  3: 'wy:string',
  4: 'wy:bool',
  5: 'wy:enum',
  6: 'wy:link',
  7: 'wy:flow',
  8: 'wy:flow-node',
  9: 'wy:broker',
  10: 'wy:metric',
};

T? _byCode<T>(List<T> values, int c, int Function(T) code) {
  for (final v in values) {
    if (code(v) == c) return v;
  }
  return null;
}

T? _byName<T>(List<T> values, String n, String Function(T) name) {
  for (final v in values) {
    if (name(v) == n) return v;
  }
  return null;
}
