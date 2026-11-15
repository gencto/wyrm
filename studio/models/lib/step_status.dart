/// How a step of a run ended (`~state.plan[n].result.status`).
enum StepStatus {
  ok,
  failed,

  /// Left out by the approver, or a step that needs one left out.
  skipped,
}
