/// What waits in quarantine, as the screens tell it apart.
enum WaitingKind {
  /// A link's certificate.
  link,

  /// A downstream broker asking for Authorize.
  broker,

  /// It was answered in a form Studio does not read: what waits is not
  /// known, and the screens say so.
  notRead,
}
