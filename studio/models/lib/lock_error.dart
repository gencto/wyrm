import 'package:freezed_annotation/freezed_annotation.dart';

part 'lock_error.freezed.dart';

/// Why the idle lock is still on after a try (ADR 0050 §1.4, board
/// `UnlockLock`): the card says it under the password.
@freezed
sealed class LockError with _$LockError {
  /// The gateway refused the password (`bad_password`).
  const factory LockError.wrongPassword() = LockErrorWrongPassword;

  /// Any other refusal, in the gateway's own words (its code, else its
  /// message).
  const factory LockError.refused(String said) = LockErrorRefused;
}
