// The typed decode boundary: a wire `Value` becomes a typed model exactly
// once, in a decoder, and a shape the decoder cannot read fails there with
// the name of the field (Studio rule 8).
//
// Rules every decoder follows:
// - a required field that is absent or of another type: [DecodeError];
// - an optional field (spec: `?`) may be absent or null; present with
//   another type it is a [DecodeError] too, never a silent null;
// - a closed set read by name or code: an unknown member is a
//   [DecodeError], unless the set is documented to grow (then the decoder
//   keeps the raw text or skips the item, as its doc comment says).

import 'dart:typed_data';

import 'tables.dart';
import 'value.dart';

/// A wire value that does not have the shape its decoder reads.
final class DecodeError implements Exception {
  /// Where: the model and the field, `GatewayDevice.platform`,
  /// `AgentTaskRecord.plan[2].level`.
  final String path;

  /// What the decoder needs there: `text`, `an integer`, `one of macos,
  /// windows, ios, android`.
  final String expected;

  /// What came: the kind of value only (`absent`, `text`, `a map`), or for
  /// an unknown member of a closed set the member itself (a name or a
  /// code, never a payload).
  final String got;

  const DecodeError(this.path, this.expected, this.got);

  /// [got] described from the value [v] that came.
  DecodeError.of(this.path, this.expected, Value? v) : got = kindOf(v);

  @override
  String toString() => 'DecodeError($path: expected $expected, got $got)';

  /// The kind of [v] for a message: never its content.
  static String kindOf(Value? v) => switch (v) {
    null => 'absent',
    VNull() => 'null',
    VBool() => 'a bool',
    VInt() => 'an integer',
    VFloat() => 'a float',
    VStr() => 'text',
    VBytes() => 'bytes',
    VArray() => 'an array',
    VMap() => 'a map',
  };
}

/// The fields of one wire map, read by a decoder. Every read names
/// `path.field` in its [DecodeError].
///
/// `x(k)` reads a required field; `xOrNull(k)` an optional one (absent or
/// null → null); `xOr(k, d)` an optional one with a default.
final class WireMap {
  final Map<String, Value> fields;

  /// The model the map is read for, the prefix of every error's path.
  final String path;

  WireMap._(this.fields, this.path);

  /// [v] as a map, or a [DecodeError] at [path].
  factory WireMap.of(Value? v, String path) => switch (v) {
    VMap(:final v) => WireMap._(v, path),
    _ => throw DecodeError.of(path, 'a map', v),
  };

  String _at(String k) => '$path.$k';

  /// The raw value of [k]; null when absent.
  Value? operator [](String k) => fields[k];

  /// [k] is present and not null.
  bool has(String k) => switch (fields[k]) {
    null || VNull() => false,
    _ => true,
  };

  Value? _opt(String k) => switch (fields[k]) {
    null || VNull() => null,
    final v => v,
  };

  Never _bad(String k, String expected) =>
      throw DecodeError.of(_at(k), expected, fields[k]);

  // ---- text ----

  String str(String k) => switch (fields[k]) {
    VStr(:final v) => v,
    _ => _bad(k, 'text'),
  };

  String? strOrNull(String k) => switch (_opt(k)) {
    null => null,
    VStr(:final v) => v,
    _ => _bad(k, 'text'),
  };

  String strOr(String k, String d) => strOrNull(k) ?? d;

  /// Optional text where an empty text means the same as absent.
  String? textOrNull(String k) => switch (strOrNull(k)) {
    null || '' => null,
    final s => s,
  };

  List<String> strings(String k) => switch (fields[k]) {
    VArray(:final v) => [
      for (final (i, s) in v.indexed)
        switch (s) {
          VStr(:final v) => v,
          _ => throw DecodeError.of('${_at(k)}[$i]', 'text', s),
        },
    ],
    _ => _bad(k, 'an array of text'),
  };

  List<String> stringsOr(String k, [List<String> d = const []]) =>
      has(k) ? strings(k) : d;

  // ---- numbers ----

  int integer(String k) => switch (fields[k]) {
    VInt(:final v) => v,
    _ => _bad(k, 'an integer'),
  };

  int? integerOrNull(String k) => switch (_opt(k)) {
    null => null,
    VInt(:final v) => v,
    _ => _bad(k, 'an integer'),
  };

  int integerOr(String k, int d) => integerOrNull(k) ?? d;

  /// An integer or a float.
  double number(String k) => switch (fields[k]) {
    VInt(:final v) => v.toDouble(),
    VFloat(:final v) => v,
    _ => _bad(k, 'a number'),
  };

  double? numberOrNull(String k) => switch (_opt(k)) {
    null => null,
    VInt(:final v) => v.toDouble(),
    VFloat(:final v) => v,
    _ => _bad(k, 'a number'),
  };

  List<int> integers(String k) => switch (fields[k]) {
    VArray(:final v) => [
      for (final (i, n) in v.indexed)
        switch (n) {
          VInt(:final v) => v,
          _ => throw DecodeError.of('${_at(k)}[$i]', 'an integer', n),
        },
    ],
    _ => _bad(k, 'an array of integers'),
  };

  List<int> integersOr(String k, [List<int> d = const []]) =>
      has(k) ? integers(k) : d;

  // ---- other scalars ----

  bool boolean(String k) => switch (fields[k]) {
    VBool(:final v) => v,
    _ => _bad(k, 'a bool'),
  };

  bool? booleanOrNull(String k) => switch (_opt(k)) {
    null => null,
    VBool(:final v) => v,
    _ => _bad(k, 'a bool'),
  };

  bool booleanOr(String k, bool d) => booleanOrNull(k) ?? d;

  Uint8List bytes(String k) => switch (fields[k]) {
    VBytes(:final v) => v,
    _ => _bad(k, 'bytes'),
  };

  Uint8List? bytesOrNull(String k) => switch (_opt(k)) {
    null => null,
    VBytes(:final v) => v,
    _ => _bad(k, 'bytes'),
  };

  // ---- closed sets ----

  /// A member of [values] by its wire name.
  T name<T extends WireName>(String k, List<T> values) {
    final s = str(k);
    return wireByName(values, s) ??
        (throw DecodeError(_at(k), _oneOf(values), "'$s'"));
  }

  T? nameOrNull<T extends WireName>(String k, List<T> values) =>
      has(k) ? name(k, values) : null;

  T nameOr<T extends WireName>(String k, List<T> values, T d) =>
      nameOrNull(k, values) ?? d;

  /// A member of [values] by its code ([VInt]) or its name ([VStr]).
  T codeOrName<T extends WireCode>(String k, List<T> values) {
    final v = fields[k];
    final found = switch (v) {
      VInt(:final v) => wireByCode(values, v),
      VStr(:final v) => wireByName(values, v),
      _ => _bad(k, 'a code or a name'),
    };
    return found ??
        (throw DecodeError(_at(k), _oneOf(values), switch (v) {
          VInt(:final v) => '$v',
          VStr(:final v) => "'$v'",
          _ => DecodeError.kindOf(v),
        }));
  }

  T? codeOrNameOrNull<T extends WireCode>(String k, List<T> values) =>
      has(k) ? codeOrName(k, values) : null;

  /// A permission level as a code or a name (spec 06 `maxperm`).
  Perm perm(String k) => codeOrName(k, Perm.values);

  Perm? permOrNull(String k) => codeOrNameOrNull(k, Perm.values);

  // ---- nested ----

  WireMap map(String k) => WireMap.of(fields[k], _at(k));

  WireMap? mapOrNull(String k) => has(k) ? map(k) : null;

  /// An array whose items [item] decodes; [item] gets each item's path.
  List<T> list<T>(String k, T Function(Value v, String path) item) =>
      switch (fields[k]) {
        VArray(:final v) => [
          for (final (i, x) in v.indexed) item(x, '${_at(k)}[$i]'),
        ],
        _ => _bad(k, 'an array'),
      };

  List<T> listOr<T>(
    String k,
    T Function(Value v, String path) item, [
    List<T> d = const [],
  ]) => has(k) ? list(k, item) : d;

  static String _oneOf<T extends WireName>(List<T> values) =>
      'one of ${values.map((v) => v.wire).join(', ')}';
}
