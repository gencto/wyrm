/// Why the log-in page fell back to the password with the key kept
/// (unlock-discover.md §2, *When it does not work*): the notice above the
/// password says it.
enum UnlockFallback {
  /// The biometric did not match too many times (`SignLockout`).
  lockedOut,

  /// The prompt was cancelled or missed, biometrics were not available,
  /// or the gateway said nothing about the key: the key did not open.
  notOpened,
}
