/// The warm standby of a broker, as its `sys` values say it (ADR 0036).
enum StandbyState {
  /// `sys/standby_connected` has not arrived yet.
  unknown,

  /// No standby follows the broker (`standby_connected` = 0).
  none,

  /// A standby follows and has every record.
  following,

  /// A standby follows but is behind (`standby_lag` > 0) or moved a fork
  /// aside (`standby_forks` > 0).
  behind,
}
