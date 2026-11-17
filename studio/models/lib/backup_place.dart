/// Where a backup goes when it is made (Studio's own choice, never on the
/// wire).
enum BackupPlace {
  /// Downloaded to this computer.
  computer,

  /// Sent to a file store by a link the host names.
  store,

  /// Kept on the broker only.
  broker,
}
