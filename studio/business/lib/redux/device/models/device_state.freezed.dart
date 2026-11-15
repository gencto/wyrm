// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DeviceState {

 bool get available; KeyKind get kind; String? get name; String? get keyId; String? get deviceId; int get added; int get lastUsed; String? get keySite; bool get stale; int get lockAfter; bool get dontAsk; bool get offered; bool get noticed; DevicePolicy? get policy; UnlockStage get stage; UnlockRefusal? get refusal; UnlockFallback? get fallback; bool get reEnable; bool get autoPrompted; bool get locked; LockError? get lockError; StepUpRequest? get stepUp; IList<GatewayDevice> get devices; IMap<String, IList<GatewayDevice>> get userDevices; bool get needPassword; String? get keyRole; bool get passwordRefused;
/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeviceStateCopyWith<DeviceState> get copyWith => _$DeviceStateCopyWithImpl<DeviceState>(this as DeviceState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DeviceState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DeviceState&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.keyId, _this.keyId) || other.keyId == _this.keyId)&&(identical(other.deviceId, _this.deviceId) || other.deviceId == _this.deviceId)&&(identical(other.added, _this.added) || other.added == _this.added)&&(identical(other.lastUsed, _this.lastUsed) || other.lastUsed == _this.lastUsed)&&(identical(other.keySite, _this.keySite) || other.keySite == _this.keySite)&&(identical(other.stale, _this.stale) || other.stale == _this.stale)&&(identical(other.lockAfter, _this.lockAfter) || other.lockAfter == _this.lockAfter)&&(identical(other.dontAsk, _this.dontAsk) || other.dontAsk == _this.dontAsk)&&(identical(other.offered, _this.offered) || other.offered == _this.offered)&&(identical(other.noticed, _this.noticed) || other.noticed == _this.noticed)&&(identical(other.policy, _this.policy) || other.policy == _this.policy)&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.refusal, _this.refusal) || other.refusal == _this.refusal)&&(identical(other.fallback, _this.fallback) || other.fallback == _this.fallback)&&(identical(other.reEnable, _this.reEnable) || other.reEnable == _this.reEnable)&&(identical(other.autoPrompted, _this.autoPrompted) || other.autoPrompted == _this.autoPrompted)&&(identical(other.locked, _this.locked) || other.locked == _this.locked)&&(identical(other.lockError, _this.lockError) || other.lockError == _this.lockError)&&(identical(other.stepUp, _this.stepUp) || other.stepUp == _this.stepUp)&&const DeepCollectionEquality().equals(other.devices, _this.devices)&&(identical(other.userDevices, _this.userDevices) || other.userDevices == _this.userDevices)&&(identical(other.needPassword, _this.needPassword) || other.needPassword == _this.needPassword)&&(identical(other.keyRole, _this.keyRole) || other.keyRole == _this.keyRole)&&(identical(other.passwordRefused, _this.passwordRefused) || other.passwordRefused == _this.passwordRefused));
}


@override
int get hashCode {
  final _this = this as DeviceState;
  return Object.hashAll([runtimeType,_this.available,_this.kind,_this.name,_this.keyId,_this.deviceId,_this.added,_this.lastUsed,_this.keySite,_this.stale,_this.lockAfter,_this.dontAsk,_this.offered,_this.noticed,_this.policy,_this.stage,_this.refusal,_this.fallback,_this.reEnable,_this.autoPrompted,_this.locked,_this.lockError,_this.stepUp,const DeepCollectionEquality().hash(_this.devices),_this.userDevices,_this.needPassword,_this.keyRole,_this.passwordRefused]);
}

@override
String toString() {
  final _this = this as DeviceState;
  return 'DeviceState(available: ${_this.available}, kind: ${_this.kind}, name: ${_this.name}, keyId: ${_this.keyId}, deviceId: ${_this.deviceId}, added: ${_this.added}, lastUsed: ${_this.lastUsed}, keySite: ${_this.keySite}, stale: ${_this.stale}, lockAfter: ${_this.lockAfter}, dontAsk: ${_this.dontAsk}, offered: ${_this.offered}, noticed: ${_this.noticed}, policy: ${_this.policy}, stage: ${_this.stage}, refusal: ${_this.refusal}, fallback: ${_this.fallback}, reEnable: ${_this.reEnable}, autoPrompted: ${_this.autoPrompted}, locked: ${_this.locked}, lockError: ${_this.lockError}, stepUp: ${_this.stepUp}, devices: ${_this.devices}, userDevices: ${_this.userDevices}, needPassword: ${_this.needPassword}, keyRole: ${_this.keyRole}, passwordRefused: ${_this.passwordRefused})';
}


}

/// @nodoc
abstract mixin class $DeviceStateCopyWith<$Res>  {
  factory $DeviceStateCopyWith(DeviceState value, $Res Function(DeviceState) _then) = _$DeviceStateCopyWithImpl;
@useResult
$Res call({
 bool available, KeyKind kind, String? name, String? keyId, String? deviceId, int added, int lastUsed, String? keySite, bool stale, int lockAfter, bool dontAsk, bool offered, bool noticed, DevicePolicy? policy, UnlockStage stage, UnlockRefusal? refusal, UnlockFallback? fallback, bool reEnable, bool autoPrompted, bool locked, LockError? lockError, StepUpRequest? stepUp, IList<GatewayDevice> devices, IMap<String, IList<GatewayDevice>> userDevices, bool needPassword, String? keyRole, bool passwordRefused
});


$DevicePolicyCopyWith<$Res>? get policy;$LockErrorCopyWith<$Res>? get lockError;$StepUpRequestCopyWith<$Res>? get stepUp;

}
/// @nodoc
class _$DeviceStateCopyWithImpl<$Res>
    implements $DeviceStateCopyWith<$Res> {
  _$DeviceStateCopyWithImpl(this._self, this._then);

  final DeviceState _self;
  final $Res Function(DeviceState) _then;

/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? available = null,Object? kind = null,Object? name = freezed,Object? keyId = freezed,Object? deviceId = freezed,Object? added = null,Object? lastUsed = null,Object? keySite = freezed,Object? stale = null,Object? lockAfter = null,Object? dontAsk = null,Object? offered = null,Object? noticed = null,Object? policy = freezed,Object? stage = null,Object? refusal = freezed,Object? fallback = freezed,Object? reEnable = null,Object? autoPrompted = null,Object? locked = null,Object? lockError = freezed,Object? stepUp = freezed,Object? devices = null,Object? userDevices = null,Object? needPassword = null,Object? keyRole = freezed,Object? passwordRefused = null,}) {
  return _then(DeviceState(
available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as KeyKind,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,keyId: freezed == keyId ? _self.keyId : keyId // ignore: cast_nullable_to_non_nullable
as String?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,keySite: freezed == keySite ? _self.keySite : keySite // ignore: cast_nullable_to_non_nullable
as String?,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,lockAfter: null == lockAfter ? _self.lockAfter : lockAfter // ignore: cast_nullable_to_non_nullable
as int,dontAsk: null == dontAsk ? _self.dontAsk : dontAsk // ignore: cast_nullable_to_non_nullable
as bool,offered: null == offered ? _self.offered : offered // ignore: cast_nullable_to_non_nullable
as bool,noticed: null == noticed ? _self.noticed : noticed // ignore: cast_nullable_to_non_nullable
as bool,policy: freezed == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as DevicePolicy?,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as UnlockStage,refusal: freezed == refusal ? _self.refusal : refusal // ignore: cast_nullable_to_non_nullable
as UnlockRefusal?,fallback: freezed == fallback ? _self.fallback : fallback // ignore: cast_nullable_to_non_nullable
as UnlockFallback?,reEnable: null == reEnable ? _self.reEnable : reEnable // ignore: cast_nullable_to_non_nullable
as bool,autoPrompted: null == autoPrompted ? _self.autoPrompted : autoPrompted // ignore: cast_nullable_to_non_nullable
as bool,locked: null == locked ? _self.locked : locked // ignore: cast_nullable_to_non_nullable
as bool,lockError: freezed == lockError ? _self.lockError : lockError // ignore: cast_nullable_to_non_nullable
as LockError?,stepUp: freezed == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as StepUpRequest?,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as IList<GatewayDevice>,userDevices: null == userDevices ? _self.userDevices : userDevices // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<GatewayDevice>>,needPassword: null == needPassword ? _self.needPassword : needPassword // ignore: cast_nullable_to_non_nullable
as bool,keyRole: freezed == keyRole ? _self.keyRole : keyRole // ignore: cast_nullable_to_non_nullable
as String?,passwordRefused: null == passwordRefused ? _self.passwordRefused : passwordRefused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DevicePolicyCopyWith<$Res>? get policy {
    if (_self.policy == null) {
    return null;
  }

  return $DevicePolicyCopyWith<$Res>(_self.policy!, (value) {
    return _then(_self.copyWith(policy: value));
  });
}/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LockErrorCopyWith<$Res>? get lockError {
    if (_self.lockError == null) {
    return null;
  }

  return $LockErrorCopyWith<$Res>(_self.lockError!, (value) {
    return _then(_self.copyWith(lockError: value));
  });
}/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepUpRequestCopyWith<$Res>? get stepUp {
    if (_self.stepUp == null) {
    return null;
  }

  return $StepUpRequestCopyWith<$Res>(_self.stepUp!, (value) {
    return _then(_self.copyWith(stepUp: value));
  });
}
}



/// @nodoc


class _DeviceState implements DeviceState {
  const _DeviceState({this.available = false, this.kind = KeyKind.none, this.name, this.keyId, this.deviceId, this.added = 0, this.lastUsed = 0, this.keySite, this.stale = false, this.lockAfter = 0, this.dontAsk = false, this.offered = false, this.noticed = false, this.policy, this.stage = UnlockStage.none, this.refusal, this.fallback, this.reEnable = true, this.autoPrompted = false, this.locked = false, this.lockError, this.stepUp, this.devices = const IListConst([]), this.userDevices = const IMapConst({}), this.needPassword = false, this.keyRole, this.passwordRefused = false});
  

@override@JsonKey() final  bool available;
@override@JsonKey() final  KeyKind kind;
@override final  String? name;
@override final  String? keyId;
@override final  String? deviceId;
@override@JsonKey() final  int added;
@override@JsonKey() final  int lastUsed;
@override final  String? keySite;
@override@JsonKey() final  bool stale;
@override@JsonKey() final  int lockAfter;
@override@JsonKey() final  bool dontAsk;
@override@JsonKey() final  bool offered;
@override@JsonKey() final  bool noticed;
@override final  DevicePolicy? policy;
@override@JsonKey() final  UnlockStage stage;
@override final  UnlockRefusal? refusal;
@override final  UnlockFallback? fallback;
@override@JsonKey() final  bool reEnable;
@override@JsonKey() final  bool autoPrompted;
@override@JsonKey() final  bool locked;
@override final  LockError? lockError;
@override final  StepUpRequest? stepUp;
@override@JsonKey() final  IList<GatewayDevice> devices;
@override@JsonKey() final  IMap<String, IList<GatewayDevice>> userDevices;
@override@JsonKey() final  bool needPassword;
@override final  String? keyRole;
@override@JsonKey() final  bool passwordRefused;

/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DeviceStateCopyWith<_DeviceState> get copyWith => __$DeviceStateCopyWithImpl<_DeviceState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DeviceState&&(identical(other.available, available) || other.available == available)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.name, name) || other.name == name)&&(identical(other.keyId, keyId) || other.keyId == keyId)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.added, added) || other.added == added)&&(identical(other.lastUsed, lastUsed) || other.lastUsed == lastUsed)&&(identical(other.keySite, keySite) || other.keySite == keySite)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.lockAfter, lockAfter) || other.lockAfter == lockAfter)&&(identical(other.dontAsk, dontAsk) || other.dontAsk == dontAsk)&&(identical(other.offered, offered) || other.offered == offered)&&(identical(other.noticed, noticed) || other.noticed == noticed)&&(identical(other.policy, policy) || other.policy == policy)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.refusal, refusal) || other.refusal == refusal)&&(identical(other.fallback, fallback) || other.fallback == fallback)&&(identical(other.reEnable, reEnable) || other.reEnable == reEnable)&&(identical(other.autoPrompted, autoPrompted) || other.autoPrompted == autoPrompted)&&(identical(other.locked, locked) || other.locked == locked)&&(identical(other.lockError, lockError) || other.lockError == lockError)&&(identical(other.stepUp, stepUp) || other.stepUp == stepUp)&&const DeepCollectionEquality().equals(other.devices, devices)&&(identical(other.userDevices, userDevices) || other.userDevices == userDevices)&&(identical(other.needPassword, needPassword) || other.needPassword == needPassword)&&(identical(other.keyRole, keyRole) || other.keyRole == keyRole)&&(identical(other.passwordRefused, passwordRefused) || other.passwordRefused == passwordRefused));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,available,kind,name,keyId,deviceId,added,lastUsed,keySite,stale,lockAfter,dontAsk,offered,noticed,policy,stage,refusal,fallback,reEnable,autoPrompted,locked,lockError,stepUp,const DeepCollectionEquality().hash(devices),userDevices,needPassword,keyRole,passwordRefused]);
}

@override
String toString() {
    return 'DeviceState(available: $available, kind: $kind, name: $name, keyId: $keyId, deviceId: $deviceId, added: $added, lastUsed: $lastUsed, keySite: $keySite, stale: $stale, lockAfter: $lockAfter, dontAsk: $dontAsk, offered: $offered, noticed: $noticed, policy: $policy, stage: $stage, refusal: $refusal, fallback: $fallback, reEnable: $reEnable, autoPrompted: $autoPrompted, locked: $locked, lockError: $lockError, stepUp: $stepUp, devices: $devices, userDevices: $userDevices, needPassword: $needPassword, keyRole: $keyRole, passwordRefused: $passwordRefused)';
}


}

/// @nodoc
abstract mixin class _$DeviceStateCopyWith<$Res> implements $DeviceStateCopyWith<$Res> {
  factory _$DeviceStateCopyWith(_DeviceState value, $Res Function(_DeviceState) _then) = __$DeviceStateCopyWithImpl;
@override @useResult
$Res call({
 bool available, KeyKind kind, String? name, String? keyId, String? deviceId, int added, int lastUsed, String? keySite, bool stale, int lockAfter, bool dontAsk, bool offered, bool noticed, DevicePolicy? policy, UnlockStage stage, UnlockRefusal? refusal, UnlockFallback? fallback, bool reEnable, bool autoPrompted, bool locked, LockError? lockError, StepUpRequest? stepUp, IList<GatewayDevice> devices, IMap<String, IList<GatewayDevice>> userDevices, bool needPassword, String? keyRole, bool passwordRefused
});


@override $DevicePolicyCopyWith<$Res>? get policy;@override $LockErrorCopyWith<$Res>? get lockError;@override $StepUpRequestCopyWith<$Res>? get stepUp;

}
/// @nodoc
class __$DeviceStateCopyWithImpl<$Res>
    implements _$DeviceStateCopyWith<$Res> {
  __$DeviceStateCopyWithImpl(this._self, this._then);

  final _DeviceState _self;
  final $Res Function(_DeviceState) _then;

/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? available = null,Object? kind = null,Object? name = freezed,Object? keyId = freezed,Object? deviceId = freezed,Object? added = null,Object? lastUsed = null,Object? keySite = freezed,Object? stale = null,Object? lockAfter = null,Object? dontAsk = null,Object? offered = null,Object? noticed = null,Object? policy = freezed,Object? stage = null,Object? refusal = freezed,Object? fallback = freezed,Object? reEnable = null,Object? autoPrompted = null,Object? locked = null,Object? lockError = freezed,Object? stepUp = freezed,Object? devices = null,Object? userDevices = null,Object? needPassword = null,Object? keyRole = freezed,Object? passwordRefused = null,}) {
  return _then(_DeviceState(
available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as KeyKind,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,keyId: freezed == keyId ? _self.keyId : keyId // ignore: cast_nullable_to_non_nullable
as String?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,keySite: freezed == keySite ? _self.keySite : keySite // ignore: cast_nullable_to_non_nullable
as String?,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,lockAfter: null == lockAfter ? _self.lockAfter : lockAfter // ignore: cast_nullable_to_non_nullable
as int,dontAsk: null == dontAsk ? _self.dontAsk : dontAsk // ignore: cast_nullable_to_non_nullable
as bool,offered: null == offered ? _self.offered : offered // ignore: cast_nullable_to_non_nullable
as bool,noticed: null == noticed ? _self.noticed : noticed // ignore: cast_nullable_to_non_nullable
as bool,policy: freezed == policy ? _self.policy : policy // ignore: cast_nullable_to_non_nullable
as DevicePolicy?,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as UnlockStage,refusal: freezed == refusal ? _self.refusal : refusal // ignore: cast_nullable_to_non_nullable
as UnlockRefusal?,fallback: freezed == fallback ? _self.fallback : fallback // ignore: cast_nullable_to_non_nullable
as UnlockFallback?,reEnable: null == reEnable ? _self.reEnable : reEnable // ignore: cast_nullable_to_non_nullable
as bool,autoPrompted: null == autoPrompted ? _self.autoPrompted : autoPrompted // ignore: cast_nullable_to_non_nullable
as bool,locked: null == locked ? _self.locked : locked // ignore: cast_nullable_to_non_nullable
as bool,lockError: freezed == lockError ? _self.lockError : lockError // ignore: cast_nullable_to_non_nullable
as LockError?,stepUp: freezed == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as StepUpRequest?,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as IList<GatewayDevice>,userDevices: null == userDevices ? _self.userDevices : userDevices // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<GatewayDevice>>,needPassword: null == needPassword ? _self.needPassword : needPassword // ignore: cast_nullable_to_non_nullable
as bool,keyRole: freezed == keyRole ? _self.keyRole : keyRole // ignore: cast_nullable_to_non_nullable
as String?,passwordRefused: null == passwordRefused ? _self.passwordRefused : passwordRefused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DevicePolicyCopyWith<$Res>? get policy {
    if (_self.policy == null) {
    return null;
  }

  return $DevicePolicyCopyWith<$Res>(_self.policy!, (value) {
    return _then(_self.copyWith(policy: value));
  });
}/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LockErrorCopyWith<$Res>? get lockError {
    if (_self.lockError == null) {
    return null;
  }

  return $LockErrorCopyWith<$Res>(_self.lockError!, (value) {
    return _then(_self.copyWith(lockError: value));
  });
}/// Create a copy of DeviceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepUpRequestCopyWith<$Res>? get stepUp {
    if (_self.stepUp == null) {
    return null;
  }

  return $StepUpRequestCopyWith<$Res>(_self.stepUp!, (value) {
    return _then(_self.copyWith(stepUp: value));
  });
}
}

// dart format on
