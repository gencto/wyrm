/// What a card of System's attention panel is about, in the order the
/// panel lists them (specs/system.md, Attention panel).
enum AttentionKind {
  /// `standby_lag` > 0 or `standby_forks` > 0.
  standbyBehind,

  /// A link whose `sys/links/<id>/state` is failed.
  linkFailed,

  /// A link certificate waiting under `sys/quarantine`.
  quarantine,

  /// A downstream broker waiting for Authorize.
  brokerWaiting,

  /// `acl_denied` has grown since the screen was last shown.
  aclGrown,

  /// `standby_connected` = 0.
  noStandby,
}
