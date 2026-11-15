import 'package:freezed_annotation/freezed_annotation.dart';

import 'refusal_code.dart';

part 'lock_error.freezed.dart';

/// Why the idle lock is still on after a try (ADR 0050 §1.4, board
/// `UnlockLock`): the card says it under the password.
@freezed
sealed class LockError with _$LockError {
  /// The gateway refused the password (`bad_password`).
  const factory LockError.wrongPassword() = LockErrorWrongPassword;

  /// The gateway refused for a reason it named with a code.
  const factory LockError.gateway(RefusalCode code) = LockErrorGateway;

  /// A refusal with no code, or a code this client does not know: the
  /// gateway's message as it is.
  const factory LockError.refused(String message) = LockErrorRefused;
}
