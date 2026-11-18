import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';

/// A field of a wire map that is not of its shape: what a reader of
/// [Fields] throws and [decoding] turns into an [Invalid].
final class BadField implements Exception {
  const BadField(this.field, this.reason);

  /// The field at fault, by its wire name; empty for the value itself.
  final String field;
  final String reason;
}

/// Runs [read] and gives its value as [Valid], or the [BadField] it threw
/// as an [Invalid] of [shape].
Decoded<T> decoding<T>(String shape, T Function() read) {
  try {
    return Valid(read());
  } on BadField catch (b) {
    return Invalid(shape, b.field, b.reason);
  }
}

/// The fields of one wire map, read strictly: a reader gives the typed
/// value or throws a [BadField] with the field's name. Nothing here turns
/// a value of another shape into a default; a field that may be absent is
/// read by a reader whose name says so (`textOr`, `flagOr`), and only an
/// absent or null value takes the default.
extension type const Fields._(Map<String, Value> _m) {
  /// The fields of [v], which must be a map.
  factory Fields.of(Value? v, [String field = '']) => switch (v) {
    VMap(:final v) => Fields._(v),
    _ => throw BadField(field, 'not a map'),
  };

  /// The attributes of a node's meta (none: no fields).
  factory Fields.attrs(NodeMeta m) =>
      Fields._(m.attr ?? const <String, Value>{});

  /// A set of live or read values by leaf.
  factory Fields.values(Map<String, Value> values) => Fields._(values);

  bool _absent(String field) => switch (_m[field]) {
    null || VNull() => true,
    _ => false,
  };

  /// The names of the fields.
  Iterable<String> get keys => _m.keys;

  /// The value of [field] as it came, or null when absent.
  Value? raw(String field) => _absent(field) ? null : _m[field];

  /// A text.
  String text(String field) => switch (_m[field]) {
    VStr(:final v) => v,
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not a text'),
  };

  /// A text, or null when absent.
  String? textOr(String field) => _absent(field) ? null : text(field);

  /// A bool.
  bool flag(String field) => switch (_m[field]) {
    VBool(:final v) => v,
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not a bool'),
  };

  /// A bool, or null when absent.
  bool? flagOr(String field) => _absent(field) ? null : flag(field);

  /// A whole number (a whole float too).
  int whole(String field) => switch (_m[field]) {
    VInt(:final v) => v,
    VFloat(:final v) when v == v.truncateToDouble() => v.toInt(),
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not a whole number'),
  };

  /// A whole number, or null when absent.
  int? wholeOr(String field) => _absent(field) ? null : whole(field);

  /// A number, or null when absent.
  num? numberOr(String field) => switch (_m[field]) {
    null || VNull() => null,
    VInt(:final v) => v,
    VFloat(:final v) => v,
    _ => throw BadField(field, 'not a number'),
  };

  /// Bytes.
  List<int> bytes(String field) => switch (_m[field]) {
    VBytes(:final v) => v,
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not bytes'),
  };

  /// A wire name read by [fromWire]; a name it does not know is refused.
  E name<E>(String field, E? Function(String wire) fromWire) =>
      fromWire(text(field)) ?? (throw BadField(field, 'not a known name'));

  /// A wire name, or null when absent; a name [fromWire] does not know is
  /// refused.
  E? nameOr<E>(String field, E? Function(String wire) fromWire) =>
      _absent(field) ? null : name(field, fromWire);

  /// An array of texts.
  List<String> texts(String field) => switch (_m[field]) {
    VArray(:final v) => [
      for (final e in v)
        switch (e) {
          VStr(:final v) => v,
          _ => throw BadField(field, 'not texts'),
        },
    ],
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not an array'),
  };

  /// An array of texts, or none when absent.
  List<String> textsOr(String field) =>
      _absent(field) ? const [] : texts(field);

  /// An array of wire names read by [fromWire].
  List<E> names<E>(String field, E? Function(String wire) fromWire) => [
    for (final t in texts(field))
      fromWire(t) ?? (throw BadField(field, 'not a known name')),
  ];

  /// A moment written as ISO 8601 text.
  DateTime moment(String field) =>
      DateTime.tryParse(text(field)) ??
      (throw BadField(field, 'not an ISO 8601 time'));

  /// A moment, or null when absent: Unix seconds, milliseconds or
  /// microseconds (told by size), or an ISO 8601 text.
  DateTime? timeOr(String field) {
    switch (_m[field]) {
      case null || VNull():
        return null;
      case VStr(:final v):
        return DateTime.tryParse(v) ??
            (throw BadField(field, 'not an ISO 8601 time'));
      case VInt() || VFloat():
        final n = whole(field);
        if (n <= 0) {
          throw BadField(field, 'not a time');
        }
        if (n < 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
        }
        if (n < 100000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
        }
        return DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true);
      default:
        throw BadField(field, 'not a time');
    }
  }

  /// A list of names, or none when absent: an array of texts, or one text
  /// of comma-separated items (how `sys/quarantine` writes `via`).
  List<String> listOr(String field) => switch (_m[field]) {
    null || VNull() => const [],
    VStr(:final v) => [
      for (final s in v.split(','))
        if (s.trim() case final t when t.isNotEmpty) t,
    ],
    _ => texts(field),
  };

  /// A map, as its entries.
  Map<String, Value> map(String field) => switch (_m[field]) {
    VMap(:final v) => v,
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not a map'),
  };

  /// An array, as its items.
  List<Value> array(String field) => switch (_m[field]) {
    VArray(:final v) => v,
    null || VNull() => throw BadField(field, 'missing'),
    _ => throw BadField(field, 'not an array'),
  };
}

/// A whole number that is the value of the entry [field] of a map.
int wholeOf(Value v, String field) => switch (v) {
  VInt(:final v) => v,
  VFloat(:final v) when v == v.truncateToDouble() => v.toInt(),
  _ => throw BadField(field, 'not a whole number'),
};

/// A text that is the value of the entry [field] of a map.
String textOf(Value v, String field) => switch (v) {
  VStr(:final v) => v,
  _ => throw BadField(field, 'not a text'),
};
