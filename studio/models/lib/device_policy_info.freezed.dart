// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_policy_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DevicePolicyInfo {

 bool get enabled; int get maxPerUser; int get passwordEveryDays; int get idleLockMaxMin;/// `none` or `config`: the gateway asks for a fresh confirmation before
/// a config-level change.
 String get stepUp; bool get allowDeviceCredential;
/// Create a copy of DevicePolicyInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DevicePolicyInfoCopyWith<DevicePolicyInfo> get copyWith => _$DevicePolicyInfoCopyWithImpl<DevicePolicyInfo>(this as DevicePolicyInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DevicePolicyInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DevicePolicyInfo&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.maxPerUser, _this.maxPerUser) || other.maxPerUser == _this.maxPerUser)&&(identical(other.passwordEveryDays, _this.passwordEveryDays) || other.passwordEveryDays == _this.passwordEveryDays)&&(identical(other.idleLockMaxMin, _this.idleLockMaxMin) || other.idleLockMaxMin == _this.idleLockMaxMin)&&(identical(other.stepUp, _this.stepUp) || other.stepUp == _this.stepUp)&&(identical(other.allowDeviceCredential, _this.allowDeviceCredential) || other.allowDeviceCredential == _this.allowDeviceCredential));
}


@override
int get hashCode {
  final _this = this as DevicePolicyInfo;
  return Object.hash(runtimeType,_this.enabled,_this.maxPerUser,_this.passwordEveryDays,_this.idleLockMaxMin,_this.stepUp,_this.allowDeviceCredential);
}

@override
String toString() {
  final _this = this as DevicePolicyInfo;
  return 'DevicePolicyInfo(enabled: ${_this.enabled}, maxPerUser: ${_this.maxPerUser}, passwordEveryDays: ${_this.passwordEveryDays}, idleLockMaxMin: ${_this.idleLockMaxMin}, stepUp: ${_this.stepUp}, allowDeviceCredential: ${_this.allowDeviceCredential})';
}


}

/// @nodoc
abstract mixin class $DevicePolicyInfoCopyWith<$Res>  {
  factory $DevicePolicyInfoCopyWith(DevicePolicyInfo value, $Res Function(DevicePolicyInfo) _then) = _$DevicePolicyInfoCopyWithImpl;
@useResult
$Res call({
 bool enabled, int maxPerUser, int passwordEveryDays, int idleLockMaxMin, String stepUp, bool allowDeviceCredential
});




}
/// @nodoc
class _$DevicePolicyInfoCopyWithImpl<$Res>
    implements $DevicePolicyInfoCopyWith<$Res> {
  _$DevicePolicyInfoCopyWithImpl(this._self, this._then);

  final DevicePolicyInfo _self;
  final $Res Function(DevicePolicyInfo) _then;

/// Create a copy of DevicePolicyInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? maxPerUser = null,Object? passwordEveryDays = null,Object? idleLockMaxMin = null,Object? stepUp = null,Object? allowDeviceCredential = null,}) {
  return _then(DevicePolicyInfo(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxPerUser: null == maxPerUser ? _self.maxPerUser : maxPerUser // ignore: cast_nullable_to_non_nullable
as int,passwordEveryDays: null == passwordEveryDays ? _self.passwordEveryDays : passwordEveryDays // ignore: cast_nullable_to_non_nullable
as int,idleLockMaxMin: null == idleLockMaxMin ? _self.idleLockMaxMin : idleLockMaxMin // ignore: cast_nullable_to_non_nullable
as int,stepUp: null == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as String,allowDeviceCredential: null == allowDeviceCredential ? _self.allowDeviceCredential : allowDeviceCredential // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _DevicePolicyInfo implements DevicePolicyInfo {
  const _DevicePolicyInfo({this.enabled = false, this.maxPerUser = 5, this.passwordEveryDays = 30, this.idleLockMaxMin = 30, this.stepUp = 'none', this.allowDeviceCredential = false});
  

@override@JsonKey() final  bool enabled;
@override@JsonKey() final  int maxPerUser;
@override@JsonKey() final  int passwordEveryDays;
@override@JsonKey() final  int idleLockMaxMin;
/// `none` or `config`: the gateway asks for a fresh confirmation before
/// a config-level change.
@override@JsonKey() final  String stepUp;
@override@JsonKey() final  bool allowDeviceCredential;

/// Create a copy of DevicePolicyInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DevicePolicyInfoCopyWith<_DevicePolicyInfo> get copyWith => __$DevicePolicyInfoCopyWithImpl<_DevicePolicyInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DevicePolicyInfo&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.maxPerUser, maxPerUser) || other.maxPerUser == maxPerUser)&&(identical(other.passwordEveryDays, passwordEveryDays) || other.passwordEveryDays == passwordEveryDays)&&(identical(other.idleLockMaxMin, idleLockMaxMin) || other.idleLockMaxMin == idleLockMaxMin)&&(identical(other.stepUp, stepUp) || other.stepUp == stepUp)&&(identical(other.allowDeviceCredential, allowDeviceCredential) || other.allowDeviceCredential == allowDeviceCredential));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled,maxPerUser,passwordEveryDays,idleLockMaxMin,stepUp,allowDeviceCredential);
}

@override
String toString() {
    return 'DevicePolicyInfo(enabled: $enabled, maxPerUser: $maxPerUser, passwordEveryDays: $passwordEveryDays, idleLockMaxMin: $idleLockMaxMin, stepUp: $stepUp, allowDeviceCredential: $allowDeviceCredential)';
}


}

/// @nodoc
abstract mixin class _$DevicePolicyInfoCopyWith<$Res> implements $DevicePolicyInfoCopyWith<$Res> {
  factory _$DevicePolicyInfoCopyWith(_DevicePolicyInfo value, $Res Function(_DevicePolicyInfo) _then) = __$DevicePolicyInfoCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, int maxPerUser, int passwordEveryDays, int idleLockMaxMin, String stepUp, bool allowDeviceCredential
});




}
/// @nodoc
class __$DevicePolicyInfoCopyWithImpl<$Res>
    implements _$DevicePolicyInfoCopyWith<$Res> {
  __$DevicePolicyInfoCopyWithImpl(this._self, this._then);

  final _DevicePolicyInfo _self;
  final $Res Function(_DevicePolicyInfo) _then;

/// Create a copy of DevicePolicyInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? maxPerUser = null,Object? passwordEveryDays = null,Object? idleLockMaxMin = null,Object? stepUp = null,Object? allowDeviceCredential = null,}) {
  return _then(_DevicePolicyInfo(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxPerUser: null == maxPerUser ? _self.maxPerUser : maxPerUser // ignore: cast_nullable_to_non_nullable
as int,passwordEveryDays: null == passwordEveryDays ? _self.passwordEveryDays : passwordEveryDays // ignore: cast_nullable_to_non_nullable
as int,idleLockMaxMin: null == idleLockMaxMin ? _self.idleLockMaxMin : idleLockMaxMin // ignore: cast_nullable_to_non_nullable
as int,stepUp: null == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as String,allowDeviceCredential: null == allowDeviceCredential ? _self.allowDeviceCredential : allowDeviceCredential // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
