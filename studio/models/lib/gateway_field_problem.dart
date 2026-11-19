/// What is wrong with what was typed in the gateway field.
enum GatewayFieldProblem {
  /// Nothing was typed.
  empty,

  /// A part is no `http`/`https` URL with a host.
  invalid,

  /// A part holds `user@` or `user:password@`: the user and the password
  /// have their own fields, and an address never carries them.
  credentials,
}
