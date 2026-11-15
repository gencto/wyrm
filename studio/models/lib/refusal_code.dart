/// A refusal the gateway named with its code (ADR 0050; the client's
/// `GatewayRefusal`, mapped once where the refusal is caught): what a lock
/// or a step-up says when it is refused for a reason it knows.
enum RefusalCode {
  deviceRemoved,
  passwordChanged,
  passwordDue,
  devicesOff,
  confirmRequired,
  passwordRequired,
  tooManyDevices,
  badPassword,
}
