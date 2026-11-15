import 'package:wyrm_core/wyrm_core.dart';

/// A level of the broker's log: `sys/log_level` (an enum node: its code,
/// `0 error … 4 trace`, or its name) and the `level` of `get_log` (by
/// name).
enum LogLevel implements WireCode {
  error(0, 'error'),
  warn(1, 'warn'),
  info(2, 'info'),
  debug(3, 'debug'),
  trace(4, 'trace');

  const LogLevel(this.code, this.wire);

  @override
  final int code;

  @override
  final String wire;

  static LogLevel? fromCode(int code) =>
      values.where((l) => l.code == code).firstOrNull;

  static LogLevel? fromWire(String wire) =>
      values.where((l) => l.wire == wire).firstOrNull;
}
