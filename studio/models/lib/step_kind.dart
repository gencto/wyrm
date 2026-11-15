/// What a step of an agent plan does (`tasks/<id>` `~state.plan[]`, the
/// `wyrm-agent run` step it is).
enum StepKind {
  set,
  invoke,
  wait,
  expect,
  sleep;

  /// The step changes something on the plant (`set`, `invoke`): it is the
  /// part of a plan a person approves.
  bool get changes => this == set || this == invoke;

  /// The step reads a value it leaves behind (`set`, `expect`, `wait`):
  /// what the Result card shows once the plan is done.
  bool get leavesValue => this == set || this == expect || this == wait;
}
