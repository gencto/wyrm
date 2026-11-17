/// What Studio knows of why a call was refused when the broker sent no
/// words of its own (docs/design/specs/errors.md: the broker's message is
/// shown as it came). The app words it in the user's language; `business`
/// names the case from the call and its status.
enum ErrorHint {
  /// `trigger` refused for rights: it needs write on the flow and the
  /// rights of what the block and the blocks after it act on.
  runDenied,

  /// `trigger` on a flow that is not running.
  runNotRunning,

  /// The broker has no `trigger` action (ADR 0040).
  runNoTrigger,

  /// The block is not one that runs by hand.
  runNotByHand,

  /// A value whose meta names no level it can be set at: Studio stages no
  /// set of it (the link would answer `not_supported`, not writable).
  notSettable,
}
