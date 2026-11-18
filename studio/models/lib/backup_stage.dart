/// What the backup dialog shows (Studio's own state, never on the wire).
enum BackupStage {
  /// The form of a broker backup.
  choose,

  /// The form of a link backup.
  link,

  /// One backup: its progress, then its result.
  job,

  /// The restore: the upload, the check, the choice.
  restore,

  /// Restored live (`mode: add`).
  restored,

  /// A `replace` was staged: the broker restarts.
  restarting,

  /// The broker is back and says the restore was applied.
  applied,

  /// The broker is back and put its state back.
  notApplied,

  /// The broker is back and says neither.
  unknown,

  /// The broker did not come back for this session.
  lost,
}
