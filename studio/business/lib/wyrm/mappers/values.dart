import 'package:wyrm_client/wyrm_client.dart';

/// A CBOR [Value] as plain Dart: null, bool, int, double, String, bytes,
/// `List<Object?>`, `Map<String, Object?>`.
Object? toDart(Value? v) => switch (v) {
  null || VNull() => null,
  VBool(:final v) => v,
  VInt(:final v) => v,
  VFloat(:final v) => v,
  VStr(:final v) => v,
  VBytes(:final v) => v,
  VArray(:final v) => [for (final e in v) toDart(e)],
  VMap(:final v) => {for (final e in v.entries) e.key: toDart(e.value)},
};

/// The text of [v], or null.
String? str(Value? v) => switch (v) {
  VStr(:final v) => v,
  _ => null,
};

/// The text of [v], also for a number or a bool; null otherwise.
String? text(Value? v) => switch (v) {
  VStr(:final v) => v,
  VInt(:final v) => '$v',
  VFloat(:final v) => '$v',
  VBool(:final v) => '$v',
  _ => null,
};

/// An integer of [v] (a whole float too), or null.
int? integer(Value? v) => switch (v) {
  VInt(:final v) => v,
  VFloat(:final v) when v == v.truncateToDouble() => v.toInt(),
  _ => null,
};

/// A number of [v], or null.
num? number(Value? v) => switch (v) {
  VInt(:final v) => v,
  VFloat(:final v) => v,
  _ => null,
};

/// A bool of [v], or null.
bool? boolean(Value? v) => switch (v) {
  VBool(:final v) => v,
  _ => null,
};

/// A list of strings: an array of texts, or one text of comma-separated
/// items (how `sys/quarantine` writes `via`).
List<String> strings(Value? v) => switch (v) {
  VArray(:final v) => [for (final e in v) ?str(e)],
  VStr(:final v) => [
    for (final s in v.split(','))
      if (s.trim() case final t when t.isNotEmpty) t,
  ],
  _ => const [],
};

/// A time: Unix seconds, milliseconds or microseconds (told by size), or an
/// ISO 8601 text. Null when it is none of these.
DateTime? time(Value? v) {
  switch (v) {
    case VStr(:final v):
      return DateTime.tryParse(v);
    case VInt() || VFloat():
      final n = number(v)!.toInt();
      if (n <= 0) {
        return null;
      }
      if (n < 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      }
      if (n < 100000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
      }
      return DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true);
    default:
      return null;
  }
}

/// `attr.<name>` of a node's meta.
Value? attrOf(NodeMeta meta, String name) => meta.attr?[name];
