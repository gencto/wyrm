/// What one line of a task's conversation is.
enum TaskEventKind {
  /// What the person asked, or answered in their own words.
  ask,

  /// A line of the model's text.
  text,

  /// A read-only tool the model called.
  tool,

  /// A question to the person (shown on the choices card).
  question,

  /// The task reached a state (`TaskEvent.state`).
  state,

  /// A refusal or a failure.
  error,

  /// A line of the record's log that says what was done.
  note,

  /// The options the person picked on the choices card.
  answer,
}
