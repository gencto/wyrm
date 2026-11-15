enum TaskState {
  planning,

  /// The assistant asked the person and waits for the answer.
  awaitingAnswer,
  awaitingApproval,
  running,
  done,
  failed;

  /// Nothing more happens to the task.
  bool get finished => this == done || this == failed;
}
