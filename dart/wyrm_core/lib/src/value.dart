// The dynamic `Value` (spec 03): the CBOR data model restricted to what
// `~meta.type` allows. Tagged, so an integral float stays a float on every
// platform (on the web `1.0 is int` is true; a `VFloat` stays a float).

import 'dart:typed_data';

import 'cbor.dart';

sealed class Value {
  const Value();

  /// Plain Dart → [Value]: `null`, `bool`, `int`, `double`, `String`,
  /// `Uint8List`, `List`, `Map<String, …>`; a [Value] passes through.
  /// On the web an integral `double` becomes a [VInt]; use [VFloat] there.
  factory Value.from(Object? o) {
    if (o is Value) return o;
    if (o == null) return const VNull();
    if (o is bool) return VBool(o);
    if (o is int) return VInt(o);
    if (o is double) return VFloat(o);
    if (o is String) return VStr(o);
    if (o is Uint8List) return VBytes(o);
    if (o is List) return VArray([for (final e in o) Value.from(e)]);
    if (o is Map) {
      final out = <String, Value>{};
      for (final e in o.entries) {
        final k = e.key;
        if (k is! String) throw ArgumentError('Value maps need text keys, got $k');
        out[k] = Value.from(e.value);
      }
      return VMap(out);
    }
    throw ArgumentError('no WYRM Value for ${o.runtimeType}');
  }

  /// Deepest nesting of arrays, maps and tags in one value (spec README,
  /// rule 6): input from anyone cannot make the decoder recurse past it.
  static const maxDepth = 32;

  static Value decode(CborReader r, [int depth = 0]) {
    if (depth > maxDepth) throw CborError('nesting deeper than $maxDepth');
    switch (r.peek()) {
      case CborType.uint:
      case CborType.nint:
        return VInt(r.readInt());
      case CborType.float:
        return VFloat(r.readFloat());
      case CborType.text:
        return VStr(r.readText());
      case CborType.bytes:
        return VBytes(r.readBytes());
      case CborType.array:
        final n = r.readArrayHeader();
        final out = <Value>[];
        if (n == null) {
          while (!r.takeBreak()) {
            out.add(decode(r, depth + 1));
          }
        } else {
          for (var i = 0; i < n; i++) {
            out.add(decode(r, depth + 1));
          }
        }
        return VArray(out);
      case CborType.map:
        final n = r.readMapHeader();
        final out = <String, Value>{};
        if (n == null) {
          while (!r.takeBreak()) {
            final k = _key(r);
            out[k] = decode(r, depth + 1);
          }
        } else {
          for (var i = 0; i < n; i++) {
            final k = _key(r);
            out[k] = decode(r, depth + 1);
          }
        }
        return VMap(out);
      case CborType.tag:
        r.skipTagHead();
        return decode(r, depth + 1);
      case CborType.simple:
        final any = r.readAny();
        if (any is bool) return VBool(any);
        return const VNull();
      case CborType.breakMark:
        throw CborError('unexpected break');
    }
  }

  static String _key(CborReader r) {
    if (r.peek() != CborType.text) throw CborError('Value map keys must be text');
    return r.readText();
  }

  void encode(CborWriter w);

  /// Canonical CBOR bytes.
  Uint8List toCbor() => encodeCbor(encode);

  /// Decode one top-level item.
  static Value fromCbor(List<int> bytes) => decodeCbor(bytes, decode);

  /// Plain Dart view (inverse of [Value.from]).
  Object? toDart();

  /// Numeric view; `null` for non-numbers.
  double? get asDouble => switch (this) {
        VInt(:final v) => v.toDouble(),
        VFloat(:final v) => v,
        _ => null,
      };

  /// Map entry, `null` if this is not a map or the key is absent.
  Value? operator [](String key) => switch (this) {
        VMap(:final v) => v[key],
        _ => null,
      };
}

final class VNull extends Value {
  const VNull();
  @override
  void encode(CborWriter w) => w.nil();
  @override
  Object? toDart() => null;
  @override
  bool operator ==(Object other) => other is VNull;
  @override
  int get hashCode => 0;
  @override
  String toString() => 'null';
}

final class VBool extends Value {
  final bool v;
  const VBool(this.v);
  @override
  void encode(CborWriter w) => w.boolean(v);
  @override
  Object? toDart() => v;
  @override
  bool operator ==(Object other) => other is VBool && other.v == v;
  @override
  int get hashCode => v.hashCode;
  @override
  String toString() => '$v';
}

/// Integer (CBOR major 0 or 1), within the signed 64-bit range.
final class VInt extends Value {
  final int v;
  const VInt(this.v);
  @override
  void encode(CborWriter w) => w.integer(v);
  @override
  Object? toDart() => v;
  @override
  bool operator ==(Object other) => other is VInt && other.v == v;
  @override
  int get hashCode => v.hashCode;
  @override
  String toString() => '$v';
}

/// Float, encoded in the shortest lossless width.
final class VFloat extends Value {
  final double v;
  const VFloat(this.v);
  @override
  void encode(CborWriter w) => w.float(v);
  @override
  Object? toDart() => v;
  @override
  bool operator ==(Object other) =>
      other is VFloat && (other.v == v || (other.v.isNaN && v.isNaN));
  @override
  int get hashCode => v.isNaN ? 1 : v.hashCode;
  @override
  String toString() => '$v';
}

final class VStr extends Value {
  final String v;
  const VStr(this.v);
  @override
  void encode(CborWriter w) => w.text(v);
  @override
  Object? toDart() => v;
  @override
  bool operator ==(Object other) => other is VStr && other.v == v;
  @override
  int get hashCode => v.hashCode;
  @override
  String toString() => '"$v"';
}

final class VBytes extends Value {
  final Uint8List v;
  const VBytes(this.v);
  @override
  void encode(CborWriter w) => w.bytes(v);
  @override
  Object? toDart() => v;
  @override
  bool operator ==(Object other) => other is VBytes && _listEq(other.v, v);
  @override
  int get hashCode => Object.hashAll(v);
  @override
  String toString() => 'h\'${hexOf(v)}\'';
}

final class VArray extends Value {
  final List<Value> v;
  const VArray(this.v);
  @override
  void encode(CborWriter w) {
    w.arrayHeader(v.length);
    for (final e in v) {
      e.encode(w);
    }
  }

  @override
  Object? toDart() => [for (final e in v) e.toDart()];
  @override
  bool operator ==(Object other) => other is VArray && _listEq(other.v, v);
  @override
  int get hashCode => Object.hashAll(v);
  @override
  String toString() => '$v';
}

/// Text-keyed map, encoded in canonical key order.
final class VMap extends Value {
  final Map<String, Value> v;
  const VMap(this.v);
  @override
  void encode(CborWriter w) => encodeTextMap(w, v, (w, x) => x.encode(w));
  @override
  Object? toDart() => {for (final e in v.entries) e.key: e.value.toDart()};
  @override
  bool operator ==(Object other) {
    if (other is! VMap || other.v.length != v.length) return false;
    for (final e in v.entries) {
      if (other.v[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(v.entries.map((e) => Object.hash(e.key, e.value)));
  @override
  String toString() => '$v';
}

/// Write a text-keyed map in canonical order.
void encodeTextMap<T>(CborWriter w, Map<String, T> m, void Function(CborWriter, T) enc) {
  final keys = m.keys.toList()..sort(canonicalTextOrder);
  w.mapHeader(keys.length);
  for (final k in keys) {
    w.text(k);
    enc(w, m[k] as T);
  }
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
