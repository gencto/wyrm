import 'package:freezed_annotation/freezed_annotation.dart';

import 'restore_end.dart';

part 'restore_record.freezed.dart';

@freezed
abstract class RestoreRecord with _$RestoreRecord {
  /// The audit record of the end of a staged restore.
  const factory RestoreRecord({
    required RestoreEnd end,

    /// When it was written, in Unix seconds.
    required int seconds,

    /// The broker's words: the sections, or why it failed.
    String? detail,
  }) = _RestoreRecord;
}
