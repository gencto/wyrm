/// What Studio knows of `sys/backups` of the site on screen.
enum BackupsRead {
  /// The broker has no `sys/backups` (a wyrmd before ADR 0048), or it was
  /// not read yet.
  absent,

  /// Its attributes were read: backups are offered.
  read,

  /// The broker has it, and its attributes came in a form this Studio
  /// does not read: no backup is offered, and the screens say why.
  unreadable,
}
