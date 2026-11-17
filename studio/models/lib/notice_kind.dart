/// A notice whose words `ui` says (studio-rules §5): what was copied, what
/// was saved.
enum NoticeKind {
  keyCopied,
  keysCopied,
  valueCopied,

  /// *Copy details* of an error.
  detailsCopied,

  /// *Copy report* of a fault in Studio.
  reportCopied,

  /// The assistant's draft (the drawer's second tile while a plan waits).
  draftCopied,

  /// A task's plan was saved as a file (`StudioNotice.path`), without the
  /// arguments in `StudioNotice.leftOut`.
  planSaved,
}
