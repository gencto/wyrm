import 'package:freezed_annotation/freezed_annotation.dart';

part 'fault_report.freezed.dart';

/// What a fault in Studio itself was (docs/design/specs/errors.md §1):
/// shown in the Details of a `studio` error and copied by *Copy report*.
@freezed
abstract class FaultReport with _$FaultReport {
  const factory FaultReport({
    /// The Dart type of what was thrown (`FormatException`).
    @Default('') String type,

    /// The first line of its text. Never a value, a token or a password:
    /// the report leaves this computer when the user sends it.
    @Default('') String line,

    /// Where it was thrown: the action, or `file › member` of the first
    /// stack frame inside Studio.
    @Default('') String where,

    /// The screen or the panel it belongs to, when known.
    String? screen,

    /// The stack trace; in the copied report only, never on screen.
    @Default('') String stack,
  }) = _FaultReport;
}
