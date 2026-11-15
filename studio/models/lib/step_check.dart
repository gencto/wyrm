/// When a step of a plan was checked against the tree.
enum StepCheck {
  /// Against the live tree, when it was proposed.
  now,

  /// When it runs: an earlier step makes its node.
  atRun,
}
