import 'package:fast_immutable_collections/fast_immutable_collections.dart';

/// A JSON value of a flow definition that the editor keeps as it came: a
/// node's config (`FlowBlock.cfg`), a parameter's default, a constant.
///
/// The definition goes back to the engine as it came, and the inspector
/// edits any parameter the catalog names by its name, so a node's config
/// stays JSON in the draft. It is read only through this type: [JsonValue.of]
/// decodes a value once (a map or a list once per object: an edit makes a
/// new one), and every reader switches over the cases below.
sealed class JsonValue {
  const JsonValue();

  /// [v] decoded. A map's keys are texts in JSON; a key that is not is
  /// written as its text. A value that is not JSON (no definition holds
  /// one) throws an [ArgumentError] naming its type.
  factory JsonValue.of(Object? v) => switch (v) {
    null => const JsonNull(),
    final bool b => JsonBool(b),
    final num n => JsonNumber(n),
    final String s => JsonText(s),
    final Map<Object?, Object?> m => _maps[m] ??= JsonMap._of(m),
    final List<Object?> l => _lists[l] ??= JsonList._of(l),
    final IMap<Object?, Object?> m => JsonValue.of(m.unlock),
    final IList<Object?> l => JsonValue.of(l.unlock),
    _ => throw ArgumentError.value(v, 'v', 'not JSON: ${v.runtimeType}'),
  };

  /// [v] decoded when it is JSON at its top; null when it is not (a live
  /// value of the wire may be bytes): a reader that only takes JSON, such
  /// as a time in microseconds, reads none there.
  static JsonValue? tryOf(Object? v) => switch (v) {
    null || bool() || num() || String() => JsonValue.of(v),
    Map<Object?, Object?>() || List<Object?>() => JsonValue.of(v),
    _ => null,
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
}

/// `true` or `false`.
final class JsonBool extends JsonValue {
  const JsonBool(this.value);

  final bool value;

  @override
  Object? get raw => value;
}

/// A number.
final class JsonNumber extends JsonValue {
  const JsonNumber(this.value);

  final num value;

  @override
  Object? get raw => value;
}

/// A text.
final class JsonText extends JsonValue {
  const JsonText(this.text);

  final String text;

  @override
  Object? get raw => text;
}

/// An array.
final class JsonList extends JsonValue {
  JsonList._of(List<Object?> list)
    : raw = list,
      items = [for (final x in list) JsonValue.of(x)].lock;

  @override
  final List<Object?> raw;

  /// Its items, decoded, in order.
  final IList<JsonValue> items;

  /// Its non-empty texts in order (the names a list parameter holds).
  List<String> get names => [
    for (final x in items)
      if (x case JsonText(:final text) when text.isNotEmpty) text,
  ];
}

/// An object.
final class JsonMap extends JsonValue {
  JsonMap._of(Map<Object?, Object?> map)
    : raw = map,
      fields = {
        for (final MapEntry(:key, :value) in map.entries)
          '$key': JsonValue.of(value),
      }.lock;

  @override
  final Map<Object?, Object?> raw;

  /// Its fields, decoded, by key.
  final IMap<String, JsonValue> fields;

  /// Its entries as the definition writes them, by key.
  Map<String, Object?> get entries => {
    for (final MapEntry(:key, :value) in fields.entries) key: value.raw,
  };
}
