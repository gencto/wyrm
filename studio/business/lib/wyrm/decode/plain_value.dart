import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/plain_entry.dart';
import 'package:models/plain_value.dart';

// A sample's value as a viewer shows it. `LiveValue.value` holds a wire
// value as plain Dart (`toDart` of `liveValueOf`: null, bool, int, double,
// String, bytes, lists and maps of these); it is read here, once per value,
// into a [PlainValue] the viewer and the table grid switch over.

/// [v] typed. Bytes are bytes (a list of numbers in JSON stays a list), a
/// map keeps its keys in order as texts (a key that is not one is marked),
/// anything else is [PlainValueOther]. A map or a list is read once: the
/// same instance gives the same [PlainValue].
PlainValue plainValueOf(Object? v) => switch (v) {
  null => const PlainValue.nothing(),
  final bool b => PlainValue.flag(b),
  final num n => PlainValue.number(n),
  final String s => PlainValue.text(s),
  // before the list: bytes are a list of numbers to Dart
  final Uint8List b => PlainValue.bytes(b),
  final Map<Object?, Object?> m => _plains[m] ??= PlainValue.map(
    entries: [
      for (final MapEntry(:key, :value) in m.entries)
        PlainEntry(
          key: '$key',
          textKey: key is String,
          value: plainValueOf(value),
        ),
    ].lock,
    raw: m,
  ),
  final List<Object?> l => _plains[l] ??= PlainValue.list(
    items: [for (final x in l) plainValueOf(x)].lock,
    raw: l,
  ),
  final Object o => PlainValue.other(
    text: '$o',
    type: o.runtimeType.toString(),
    raw: o,
  ),
};

final _plains = Expando<PlainValue>('plain values');

/// [text] read as JSON, typed; null when it is no JSON.
PlainValue? plainJsonOf(String text) {
  try {
    return plainValueOf(jsonDecode(text));
  } on FormatException {
    return null;
  }
}
