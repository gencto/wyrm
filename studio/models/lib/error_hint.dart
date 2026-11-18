/// What Studio knows of why a call was refused when the broker sent no
/// words of its own (docs/design/specs/errors.md: the broker's message is
/// shown as it came). The app words it in the user's language; `business`
/// names the case from the call and its status.
enum ErrorHint {
  /// `trigger` refused for rights: it needs write on the flow and the
  /// rights of what the block and the blocks after it act on.
  runDenied,

  /// `trigger` on a flow that is not running.
  runNotRunning,

  /// The broker has no `trigger` action (ADR 0040).
  runNoTrigger,

  /// The block is not one that runs by hand.
  runNotByHand,

  /// A value whose meta names no level it can be set at: Studio stages no
  /// set of it (the link would answer `not_supported`, not writable).
  notSettable,

  /// The broker answered, and the answer is not of the shape the call
  /// has: Studio reads nothing out of it (the field is in the log).
  unreadableAnswer,

  /// A list was read, and some of its entries are not of the shape they
  /// have: Studio shows the others and names these (their fields are in
  /// the log).
  unreadableRows,

  /// A file the user picked is not of the form its kind has (a profile
  /// that is no profile): nothing of it was sent. The field at fault is
  /// in the error and in the log.
  fileNotRead,

  /// The broker shows no SHA-256 of a backup: what arrives cannot be
  /// checked, so nothing was downloaded.
  backupNoDigest,

  /// The file that arrived is not the backup: its SHA-256 is not the one
  /// the broker shows (both are in the log). Nothing was saved.
  backupDigestMismatch,
}
