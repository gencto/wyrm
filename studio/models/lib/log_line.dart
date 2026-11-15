import 'package:freezed_annotation/freezed_annotation.dart';

import 'log_level.dart';

part 'log_line.freezed.dart';

/// One record of a `get_log` answer (`sys` or `sys/links/<id>`).
@freezed
abstract class LogLine with _$LogLine {
  const factory LogLine({
    /// As the broker wrote it (ISO 8601, UTC): what Copy and Save write.
    @Default('') String time,

    /// [time] read; null when it is not a time.
    DateTime? at,

    /// None when the record names none.
    LogLevel? level,

    /// The module (or the `link{id=…}` span) that logged it.
    @Default('') String target,
    @Default('') String message,
  }) = _LogLine;
}
