import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_policy_info.freezed.dart';

/// `gateway.devices` as the gateway's `/api/info` tells it (ADR 0050 §1.6):
/// what the log-in page may offer and how long the idle lock may wait.
@freezed
abstract class DevicePolicyInfo with _$DevicePolicyInfo {
  const factory DevicePolicyInfo({
    @Default(false) bool enabled,
    @Default(5) int maxPerUser,
    @Default(30) int passwordEveryDays,
    @Default(30) int idleLockMaxMin,

    /// `none` or `config`: the gateway asks for a fresh confirmation before
    /// a config-level change.
    @Default('none') String stepUp,
    @Default(false) bool allowDeviceCredential,
  }) = _DevicePolicyInfo;
}
