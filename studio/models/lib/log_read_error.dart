import 'package:freezed_annotation/freezed_annotation.dart';

part 'log_read_error.freezed.dart';

/// Why the last `get_log` gave no lines (specs/system.md, States): the
/// broker refused it, or its answer is not a log. Shown in the log box,
/// worded by `ui`; the lines held stay.
@freezed
sealed class LogReadError with _$LogReadError {
  /// The broker refused: its status name (`permission_denied`) and its
  /// message, as it wrote them.
  const factory LogReadError.refused(String status, String message) =
      LogRefused;

  /// The answer is not a log: the field at fault and why (the decoder's
  /// own words, `level: not a level name`).
  const factory LogReadError.invalid(String field, String reason) =
      LogInvalid;
}
