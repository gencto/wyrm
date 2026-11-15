/// The state of a link, `sys/links/<id>/state` (wyrm-admin `STATES`): an
/// enum code on the wire, in this order.
enum LinkState {
  installed('installed'),
  starting('starting'),
  connected('connected'),
  stopping('stopping'),
  stopped('stopped'),
  failed('failed');

  const LinkState(this.wire);

  /// The state's name on the wire (the value's enum name).
  final String wire;

  /// The state of the code [code]; null for one this client does not know.
  static LinkState? fromCode(int code) =>
      code >= 0 && code < values.length ? values[code] : null;

  /// The state named [name]; null for one this client does not know.
  static LinkState? fromWire(String name) =>
      values.where((s) => s.wire == name).firstOrNull;
}
