/// What Studio knows of `sys/backups` of the site on screen.
enum BackupsRead {
  /// It was not read yet: nothing is known, and nothing is said of the
  /// broker.
  unknown,

  /// The broker has no `sys/backups` (a wyrmd before ADR 0048): it said
  /// so.
  absent,

  /// Its attributes were read: backups are offered.
  read,

  /// The broker has it, and its attributes came in a form this Studio
  /// does not read: no backup is offered, and the screens say why.
  unreadable,

  /// The read failed (no answer, a refusal): whether the broker makes
  /// backups is not known. The screens say so and offer to read again.
  failed,
}
