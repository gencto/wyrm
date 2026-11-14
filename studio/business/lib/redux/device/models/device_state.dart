import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/device_policy_info.dart';
import 'package:models/key_kind.dart';
import 'package:models/step_up_request.dart';
import 'package:models/unlock_refusal.dart';
import 'package:models/unlock_stage.dart';
import 'package:models/user_device.dart';

part 'device_state.freezed.dart';

@freezed
abstract class DeviceState with _$DeviceState {
  const factory DeviceState({
    @Default(false) bool available,
    @Default(KeyKind.none) KeyKind kind,
    String? name,
    String? keyId,
    String? deviceId,
    @Default(0) int added,
    @Default(0) int lastUsed,
    String? keySite,
    @Default(false) bool stale,
    @Default(0) int lockAfter,
    @Default(false) bool dontAsk,
    @Default(false) bool offered,
    @Default(false) bool noticed,
    DevicePolicyInfo? policy,
    @Default(UnlockStage.none) UnlockStage stage,
    UnlockRefusal? refusal,
    String? reason,
    @Default(true) bool reEnable,
    @Default(false) bool autoPrompted,
    @Default(false) bool locked,
    String? lockError,
    StepUpRequest? stepUp,
    @Default(IListConst([])) IList<UserDevice> devices,
    @Default(IMapConst({})) IMap<String, IList<UserDevice>> userDevices,
    @Default(false) bool needPassword,
    String? securityError,
    String? keyRole,
  }) = _DeviceState;
}
