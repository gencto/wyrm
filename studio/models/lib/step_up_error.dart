import 'package:freezed_annotation/freezed_annotation.dart';

part 'step_up_error.freezed.dart';

/// Why the last try of the step-up dialog failed (ADR 0050 §1.3, board
/// `UnlockStepUp`); the dialog stays open and says it.
@freezed
sealed class StepUpError with _$StepUpError {
  /// The gateway refused the password (`bad_password`).
  const factory StepUpError.wrongPassword() = StepUpWrongPassword;

  /// The OS prompt gave no signature: cancelled, locked out, or no
  /// biometric now.
  const factory StepUpError.stopped() = StepUpStopped;

  /// The key no longer opens (fingerprints or faces changed).
  const factory StepUpError.keyGone() = StepUpKeyGone;

  /// The gateway or the OS refused, in its own words (the gateway's code,
  /// else its message; the OS's message).
  const factory StepUpError.refused(String said) = StepUpRefused;
}
