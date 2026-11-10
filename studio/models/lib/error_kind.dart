/// What kind of failure an error is (docs/design/specs/errors.md §1): the
/// kind picks the tone, the icon, the "what you can do" lines and the main
/// button; the title and the broker's message come from the call.
enum ErrorKind {
  /// `permission_denied`.
  rights,

  /// `timeout`, `disconnected`, `not_available`, `closed`.
  reach,

  /// `invalid_parameter`, `invalid_message`, `out_of_range`.
  input,

  /// `busy`, `rate_limited`, `resource_exhausted`.
  busy,

  /// `not_found`, `not_supported`.
  gone,

  /// `internal_error`, a `{success: false}` answer, and every status Studio
  /// does not know (user-defined 0x40–0x4F, unknown codes).
  broker,

  /// Anything that did not come from the broker: a fault in Studio.
  studio,
}
