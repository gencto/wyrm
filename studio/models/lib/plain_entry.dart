import 'package:freezed_annotation/freezed_annotation.dart';

import 'plain_value.dart';

part 'plain_entry.freezed.dart';

/// One field of a [PlainValueMap], in the map's order.
@freezed
abstract class PlainEntry with _$PlainEntry {
  const factory PlainEntry({
    /// The key as text (a key of the wire may be a number: `1`).
    required String key,

    /// The key was a text (JSON holds only those).
    required bool textKey,
    required PlainValue value,
  }) = _PlainEntry;
}
