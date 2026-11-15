import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'log_level.dart';
import 'sys_value.dart';

part 'sys_status.freezed.dart';

/// What the broker serves about itself under `sys` (specs/system.md,
/// Data), decoded once from its live values: a value that has not arrived
/// is absent.
@freezed
abstract class SysStatus with _$SysStatus {
  const factory SysStatus({
    @Default(IMapConst({})) IMap<SysValue, num> numbers,

    /// `sys/version`, `sys/zenoh_version`, `sys/distribution`.
    String? version,
    String? zenohVersion,
    String? distribution,

    /// `sys/start_time`.
    DateTime? startTime,

    /// `sys/log_level`.
    LogLevel? logLevel,
  }) = _SysStatus;

  const SysStatus._();

  /// The number [v], or null before it arrived.
  num? operator [](SysValue v) => numbers[v];

  /// `uptime` as a duration.
  Duration? get uptime => switch (numbers[SysValue.uptime]) {
    final s? => Duration(seconds: s.round()),
    null => null,
  };
}
