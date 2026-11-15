/// What kind of problem a `FlowProblem` is.
enum FlowProblemKind {
  /// A new flow has no name yet: it cannot be checked.
  unnamed,

  /// The broker refused the definition, in its own words.
  broker,

  /// The broker's answer could not be read (no `{ok, error}`).
  unread,
}
