import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart' show immutable;

/// A JSON value of a flow definition that the editor keeps as it came: a
/// node's config (`FlowBlock.cfg`), a parameter's default, a constant.
///
/// The definition goes back to the engine as it came, and the inspector
/// edits any parameter the catalog names by its name, so a node's config
/// stays JSON in the draft. It is read only through this type: [JsonValue.of]
/// decodes a value once (a map or a list once per object: an edit makes a
/// new one), and every reader switches over the cases below.
///
/// Two values are equal when they hold the same JSON (a number by its
/// value: `1` and `1.0` are one number), so a model that holds one
/// compares by what it holds.
@immutable
sealed class JsonValue {
  const JsonValue();

  /// [v] decoded. A map's keys are texts in JSON; a key that is not is
  /// written as its text. A value that is not JSON (no definition holds
  /// one) throws an [ArgumentError] naming its type; one nested deeper
  /// than [maxDepth] throws a [JsonTooDeep].
  factory JsonValue.of(Object? v) => JsonValue._at(v, 0);

  factory JsonValue._at(Object? v, int depth) {
    if (depth > maxDepth) {
      throw const JsonTooDeep();
    }
    return switch (v) {
      // Bytes are a list of numbers to Dart, not JSON.
      TypedData() => throw ArgumentError.value(v, 'v', 'not JSON: bytes'),
      null => const JsonNull(),
      final bool b => JsonBool(b),
      final num n => JsonNumber(n),
      final String s => JsonText(s),
      final Map<Object?, Object?> m => _maps[m] ??= JsonMap._of(m, depth),
      final List<Object?> l => _lists[l] ??= JsonList._of(l, depth),
      final IMap<Object?, Object?> m => JsonValue._at(m.unlock, depth),
      final IList<Object?> l => JsonValue._at(l.unlock, depth),
      _ => throw ArgumentError.value(v, 'v', 'not JSON: ${v.runtimeType}'),
    };
  }

  /// The deepest a value may nest (a list in a list in …). A file a
  /// person brings can nest without end; decoding walks the value, so a
  /// deeper one is refused ([JsonTooDeep]) instead of exhausting the
  /// stack. No definition or manifest comes near it.
  static const maxDepth = 64;

  /// [v] decoded when it is JSON through and through; null when it is
  /// not (a live value of the wire may hold bytes) or nests deeper than
  /// [maxDepth]: a reader of live values that only takes JSON, such as a
  /// time in microseconds or a short mark for a map, reads none there. A
  /// definition never holds one: its decoder refuses it.
  static JsonValue? tryOf(Object? v) => isJson(v) ? JsonValue.of(v) : null;

  /// Whether [v] is JSON through and through (no bytes inside, and not
  /// nested deeper than [maxDepth]).
  static bool isJson(Object? v) => _isJson(v, 0);

  static bool _isJson(Object? v, int depth) =>
      depth <= maxDepth &&
      switch (v) {
        TypedData() => false,
        null || bool() || num() || String() => true,
        final Map<Object?, Object?> m => m.values.every(
          (x) => _isJson(x, depth + 1),
        ),
        final List<Object?> l => l.every((x) => _isJson(x, depth + 1)),
        final IMap<Object?, Object?> m => m.values.every(
          (x) => _isJson(x, depth + 1),
        ),
        final IList<Object?> l => l.every((x) => _isJson(x, depth + 1)),
        _ => false,
      };

  static final _maps = Expando<JsonMap>('json map');
  static final _lists = Expando<JsonList>('json list');

  /// The value as the definition writes it.
  Object? get raw;
}

/// `null`.
final class JsonNull extends JsonValue {
  const JsonNull();

  @override
  Object? get raw => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => 0;
}

/// `true` or `false`.
final class JsonBool extends JsonValue {
  const JsonBool(this.value);

  final bool value;

  @override
  Object? get raw => value;

  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A number.
final class JsonNumber extends JsonValue {
  const JsonNumber(this.value);

  final num value;

  @override
  Object? get raw => value;

  @override
  bool operator ==(Object other) => other is JsonNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A text.
final class JsonText extends JsonValue {
  const JsonText(this.text);

  final String text;

  @override
  Object? get raw => text;

  @override
  bool operator ==(Object other) => other is JsonText && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// An array.
final class JsonList extends JsonValue {
  JsonList._of(List<Object?> list, int depth)
    : raw = list,
      items = [for (final x in list) JsonValue._at(x, depth + 1)].lock;

  @override
  final List<Object?> raw;

  /// Its items, decoded, in order.
  final IList<JsonValue> items;

  @override
  bool operator ==(Object other) => other is JsonList && other.items == items;

  @override
  int get hashCode => items.hashCode;

  /// Its non-empty texts in order (the names a list parameter holds).
  List<String> get names => [
    for (final x in items)
      if (x case JsonText(:final text) when text.isNotEmpty) text,
  ];
}

/// An object.
final class JsonMap extends JsonValue {
  JsonMap._of(Map<Object?, Object?> map, int depth)
    : raw = map,
      fields = {
        for (final MapEntry(:key, :value) in map.entries)
          '$key': JsonValue._at(value, depth + 1),
      }.lock;

  @override
  final Map<Object?, Object?> raw;

  /// Its fields, decoded, by key.
  final IMap<String, JsonValue> fields;

  @override
  bool operator ==(Object other) => other is JsonMap && other.fields == fields;

  @override
  int get hashCode => fields.hashCode;

  /// Its entries as the definition writes them, by key.
  Map<String, Object?> get entries => {
    for (final MapEntry(:key, :value) in fields.entries) key: value.raw,
  };
}

/// A value nests deeper than [JsonValue.maxDepth]: it is not decoded.
final class JsonTooDeep implements Exception {
  const JsonTooDeep();

  @override
  String toString() => 'JSON nested deeper than ${JsonValue.maxDepth}';
}
