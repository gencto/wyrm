enum TaskState {
  planning,

  /// The assistant asked the person and waits for the answer.
  awaitingAnswer,
  awaitingApproval,
  running,
  done,
  failed,
}
