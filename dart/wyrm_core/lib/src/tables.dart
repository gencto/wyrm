// Code tables from spec/tables.json. `test/tables_test.dart` checks that
// every enum here equals its table: same codes, same names, both ways.
//
// Each enum carries its wire code (`code`) and its spec name (`wire`), and
// is read back with `fromCode` / `fromWire`. Those return null for a code or
// a name the table lacks; a decoder turns that into a `DecodeError` that
// names the field (`decode.dart`).

import 'value.dart';

/// A closed set that crosses the wire by name.
abstract interface class WireName {
  /// The name on the wire.
  String get wire;
}

/// A closed set that crosses the wire by code and has a spec name.
abstract interface class WireCode implements WireName {
  /// The code on the wire.
  int get code;
}

/// Value quality (spec 03, key 1).
enum Quality implements WireCode {
  good(0, 'good'),
  uncertain(1, 'uncertain'),
  bad(2, 'bad');

  @override
  final int code;
  @override
  final String wire;
  const Quality(this.code, this.wire);

  /// Alias of [wire].
  String get wireName => wire;

  static Quality? fromCode(int c) => _byCode(values, c);
  static Quality? fromWire(String n) => _byWire(values, n);

  /// Alias of [fromWire].
  static Quality? fromName(String n) => fromWire(n);

  /// A code ([VInt]) or a name ([VStr]); null for anything else.
  static Quality? fromValue(Value? v) => _byValue(values, v);
}

/// Permission level (spec 04), ordered `none < list < … < config`.
enum Perm implements WireCode {
  none(0, 'none'),
  list(1, 'list'),
  read(2, 'read'),
  write(3, 'write'),
  config(4, 'config');

  @override
  final int code;
  @override
  final String wire;
  const Perm(this.code, this.wire);

  /// Alias of [wire].
  String get wireName => wire;

  static Perm? fromCode(int c) => _byCode(values, c);
  static Perm? fromWire(String n) => _byWire(values, n);

  /// Alias of [fromWire].
  static Perm? fromName(String n) => fromWire(n);

  /// A code ([VInt]: a `ptok`, `~meta.invokable`) or a name ([VStr]:
  /// `/api/me`, an agent step's `level`); spec 06 `permissions.maxperm`
  /// takes either. Null for anything else.
  static Perm? fromValue(Value? v) => _byValue(values, v);

  /// `this` is at least [other].
  bool operator >=(Perm other) => code >= other.code;
  bool operator >(Perm other) => code > other.code;
  bool operator <=(Perm other) => code <= other.code;
  bool operator <(Perm other) => code < other.code;
}

/// `~meta.writable` (spec 02, key 4).
enum Writable implements WireCode {
  never(0, 'never'),
  config(1, 'config'),
  write(2, 'write');

  @override
  final int code;
  @override
  final String wire;
  const Writable(this.code, this.wire);

  /// Alias of [wire].
  String get wireName => wire;

  static Writable? fromCode(int c) => _byCode(values, c);
  static Writable? fromWire(String n) => _byWire(values, n);
  static Writable? fromValue(Value? v) => _byValue(values, v);
}

/// Value type code (spec 02, key 1).
enum TypeCode implements WireCode {
  null_(0, 'null'),
  number(1, 'number'),
  string(2, 'string'),
  bool_(3, 'bool'),
  enum_(4, 'enum'),
  map(5, 'map'),
  array(6, 'array'),
  binary(7, 'binary'),
  dynamic_(8, 'dynamic');

  @override
  final int code;
  @override
  final String wire;
  const TypeCode(this.code, this.wire);

  /// Alias of [wire].
  String get wireName => wire;

  static TypeCode? fromCode(int c) => _byCode(values, c);
  static TypeCode? fromWire(String n) => _byWire(values, n);
  static TypeCode? fromValue(Value? v) => _byValue(values, v);
}

/// Status codes (spec 04).
enum Status implements WireCode {
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

  @override
  final int code;
  @override
  final String wire;
  const Status(this.code, this.wire);

  /// Alias of [wire].
  String get wireName => wire;

  static Status? fromCode(int c) => _byCode(values, c);
  static Status? fromWire(String n) => _byWire(values, n);
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
  String get name => known?.wire ?? (isUser ? 'user_$code' : 'unknown_$code');

  @override
  bool operator ==(Object other) => other is StatusCode && other.code == code;
  @override
  int get hashCode => code;
  @override
  String toString() => name;
}

/// Interned profile codes (`is_codes`, spec 02 key 0).
enum IsCode implements WireCode {
  node(0, 'wy:node'),
  folder(1, 'wy:folder'),
  number(2, 'wy:number'),
  string(3, 'wy:string'),
  bool_(4, 'wy:bool'),
  enum_(5, 'wy:enum'),
  link(6, 'wy:link'),
  flow(7, 'wy:flow'),
  flowNode(8, 'wy:flow-node'),
  broker(9, 'wy:broker'),
  metric(10, 'wy:metric');

  @override
  final int code;
  @override
  final String wire;
  const IsCode(this.code, this.wire);

  static IsCode? fromCode(int c) => _byCode(values, c);
  static IsCode? fromWire(String n) => _byWire(values, n);
}

/// Interned profile codes (`is_codes`) as a map; [IsCode] is the enum.
final Map<int, String> isCodes = {
  for (final c in IsCode.values) c.code: c.wire,
};

/// `agg` of `~val?history=` (spec 01): the rollup of each window.
enum HistoryAgg implements WireName {
  avg('avg'),
  min('min'),
  max('max'),
  sum('sum'),
  count('count'),
  first('first'),
  last('last'),
  delta('delta'),
  and('and'),
  or('or');

  @override
  final String wire;
  const HistoryAgg(this.wire);

  static HistoryAgg? fromWire(String n) => _byWire(values, n);
}

/// The document suffixes of a node (spec 01) that the gateway's `doc` op
/// reads.
enum DocSuffix implements WireName {
  /// `~state`: a link's restricted record (an agent task's record).
  state('~state'),

  /// `~def`: a flow's definition.
  def('~def');

  @override
  final String wire;
  const DocSuffix(this.wire);

  static DocSuffix? fromWire(String n) => _byWire(values, n);
}

T? _byCode<T extends WireCode>(List<T> values, int c) {
  for (final v in values) {
    if (v.code == c) return v;
  }
  return null;
}

T? _byWire<T extends WireName>(List<T> values, String n) {
  for (final v in values) {
    if (v.wire == n) return v;
  }
  return null;
}

T? _byValue<T extends WireCode>(List<T> values, Value? v) => switch (v) {
  VInt(:final v) => _byCode(values, v),
  VStr(:final v) => _byWire(values, v),
  _ => null,
};

/// The member of [values] named [name] on the wire, or null.
T? wireByName<T extends WireName>(List<T> values, String name) =>
    _byWire(values, name);

/// The member of [values] with wire code [code], or null.
T? wireByCode<T extends WireCode>(List<T> values, int code) =>
    _byCode(values, code);
