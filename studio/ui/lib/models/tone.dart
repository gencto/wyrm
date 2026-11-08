/// The colour role of a state mark, a pill, a notice or a row
/// (board *Design system* §05: each state is a word plus a mark that also
/// differs in shape or fill, so it reads without colour).
enum Tone {
  /// Good quality, connected, deployed.
  good,

  /// Uncertain, connecting, in quarantine.
  warn,

  /// Bad, failed, an invalid field.
  bad,

  /// Staged, selected, the primary action.
  ember,

  /// No state colour: stopped, new, stale.
  neutral,
}

/// The shape of a state mark.
enum Mark {
  /// A filled dot: good, connected, failed.
  dot,

  /// An empty ring: uncertain, connecting, new, not applied.
  ring,

  /// A cross: a bad value.
  cross,

  /// A dashed ring: stale.
  dashed,

  /// A tick: read back, ok.
  check,

  /// No mark.
  none,
}
