/// Why the agent link did not note a finding of the model
/// (`~state.findings_refused`).
enum FindingRefusal {
  rightsUnknown,
  rightsExpired,
  outsideRights,
  limit,
  invalid,
}
