import 'package:freezed_annotation/freezed_annotation.dart';

part 'call_refusal.freezed.dart';

/// A call the broker refused, kept for the screen that shows it in place:
/// the status by its wire name, the broker's own words, and the key the
/// call was made on when the screen names it. The screen writes the line.
@freezed
abstract class CallRefusal with _$CallRefusal {
  const factory CallRefusal({
    /// The status by its wire name (`permission_denied`).
    required String status,

    /// The broker's words, as they came; empty when it sent none.
    @Default('') String message,

    /// The key the call was made on, when the screen names it.
    String? key,
  }) = _CallRefusal;
}
