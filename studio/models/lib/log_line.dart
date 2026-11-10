import 'package:freezed_annotation/freezed_annotation.dart';

part 'log_line.freezed.dart';

/// One record of a `get_log` answer (`sys` or `sys/links/<id>`).
@freezed
abstract class LogLine with _$LogLine {
  const factory LogLine({
    /// As the broker wrote it (ISO 8601, UTC).
    @Default('') String time,

    /// `error`, `warn`, `info`, `debug`, `trace`.
    @Default('') String level,

    /// The module (or the `link{id=…}` span) that logged it.
    @Default('') String target,
    @Default('') String message,
  }) = _LogLine;
}
