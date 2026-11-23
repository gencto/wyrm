import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'plain_entry.dart';

part 'plain_value.freezed.dart';

/// Any value a sample holds (`LiveValue.value`: a wire value as plain
/// Dart), typed for showing it: a viewer, a table's cell. Unlike a
/// [JsonValue] of a definition, it may hold bytes and keys that are not
/// texts, and nothing about it is refused.
///
/// [raw] is the value as it came (a map or a list the same instance), for
/// what writes it back or keeps it by identity.
@freezed
sealed class PlainValue with _$PlainValue {
  const PlainValue._();

  /// `null`.
  const factory PlainValue.nothing() = PlainValueNothing;

  /// A bool.
  const factory PlainValue.flag(bool value) = PlainValueFlag;

  /// A number.
  const factory PlainValue.number(num value) = PlainValueNumber;

  /// A text.
  const factory PlainValue.text(String text) = PlainValueText;

  /// Bytes.
  const factory PlainValue.bytes(Uint8List bytes) = PlainValueBytes;

  /// A list: its [items] in order.
  const factory PlainValue.list({
    required IList<PlainValue> items,
    required Object raw,
  }) = PlainValueList;

  /// A map: its [entries] in order.
  const factory PlainValue.map({
    required IList<PlainEntry> entries,
    required Object raw,
  }) = PlainValueMap;

  /// Anything else: its [text] as Dart writes it and the name of its
  /// [type].
  const factory PlainValue.other({
    required String text,
    required String type,
    required Object raw,
  }) = PlainValueOther;

  /// The value as it came.
  Object? get raw => switch (this) {
    PlainValueNothing() => null,
    PlainValueFlag(:final value) => value,
    PlainValueNumber(:final value) => value,
    PlainValueText(:final text) => text,
    PlainValueBytes(:final bytes) => bytes,
    PlainValueList(:final raw) => raw,
    PlainValueMap(:final raw) => raw,
    PlainValueOther(:final raw) => raw,
  };
}
