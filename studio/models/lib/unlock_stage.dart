/// What the log-in page shows of the device unlock
/// (studio/docs/design/specs/unlock-discover.md §2).
enum UnlockStage {
  /// The password form as login.md has it.
  none,

  /// After a password login: `Unlock with <name> next time?`.
  offer,

  /// `Welcome back`: the account card and the round button.
  unlock,

  /// The key was signed; the gateway checks it.
  checking,

  /// Cancelled, missed or locked out: the password, the key kept.
  fallback,

  /// Fingerprints or faces changed: the key is gone.
  changed,

  /// The gateway refused the key (`UnlockRefusal`).
  signedOut,

  /// No biometric unlock on this computer (Linux): said once.
  noBiometrics,
}
