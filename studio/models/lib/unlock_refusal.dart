/// Why the gateway refused a device login (ADR 0050 §1.2, decisions 1, 7).
enum UnlockRefusal {
  /// `device_removed`: an administrator removed this device.
  removed,

  /// `password_changed`: a new password or *Sign out everywhere*.
  passwordChanged,

  /// `password_due`: the password is due again; the key stays.
  passwordDue,

  /// `devices_off`: the gateway allows no device unlock.
  devicesOff,

  /// A bare refusal: the gateway does not know this key.
  unknown,
}
