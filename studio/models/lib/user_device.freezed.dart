// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_device.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UserDevice {

 String get id; String get name;/// `mac`, `windows`, `ios`, `android`.
 String get platform;/// Seconds since the Unix epoch; 0 when not known.
 int get added; int get lastUsed; int get passwordDueAt;/// `active`, `removed` (by an administrator) or `signed_out`.
 String get state;/// The device of this session.
 bool get thisDevice;/// `user:<admin>` who removed it.
 String? get removedBy;
/// Create a copy of UserDevice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserDeviceCopyWith<UserDevice> get copyWith => _$UserDeviceCopyWithImpl<UserDevice>(this as UserDevice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserDevice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserDevice&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.platform, _this.platform) || other.platform == _this.platform)&&(identical(other.added, _this.added) || other.added == _this.added)&&(identical(other.lastUsed, _this.lastUsed) || other.lastUsed == _this.lastUsed)&&(identical(other.passwordDueAt, _this.passwordDueAt) || other.passwordDueAt == _this.passwordDueAt)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.thisDevice, _this.thisDevice) || other.thisDevice == _this.thisDevice)&&(identical(other.removedBy, _this.removedBy) || other.removedBy == _this.removedBy));
}


@override
int get hashCode {
  final _this = this as UserDevice;
  return Object.hash(runtimeType,_this.id,_this.name,_this.platform,_this.added,_this.lastUsed,_this.passwordDueAt,_this.state,_this.thisDevice,_this.removedBy);
}

@override
String toString() {
  final _this = this as UserDevice;
  return 'UserDevice(id: ${_this.id}, name: ${_this.name}, platform: ${_this.platform}, added: ${_this.added}, lastUsed: ${_this.lastUsed}, passwordDueAt: ${_this.passwordDueAt}, state: ${_this.state}, thisDevice: ${_this.thisDevice}, removedBy: ${_this.removedBy})';
}


}

/// @nodoc
abstract mixin class $UserDeviceCopyWith<$Res>  {
  factory $UserDeviceCopyWith(UserDevice value, $Res Function(UserDevice) _then) = _$UserDeviceCopyWithImpl;
@useResult
$Res call({
 String id, String name, String platform, int added, int lastUsed, int passwordDueAt, String state, bool thisDevice, String? removedBy
});




}
/// @nodoc
class _$UserDeviceCopyWithImpl<$Res>
    implements $UserDeviceCopyWith<$Res> {
  _$UserDeviceCopyWithImpl(this._self, this._then);

  final UserDevice _self;
  final $Res Function(UserDevice) _then;

/// Create a copy of UserDevice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? platform = null,Object? added = null,Object? lastUsed = null,Object? passwordDueAt = null,Object? state = null,Object? thisDevice = null,Object? removedBy = freezed,}) {
  return _then(UserDevice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,passwordDueAt: null == passwordDueAt ? _self.passwordDueAt : passwordDueAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,thisDevice: null == thisDevice ? _self.thisDevice : thisDevice // ignore: cast_nullable_to_non_nullable
as bool,removedBy: freezed == removedBy ? _self.removedBy : removedBy // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _UserDevice implements UserDevice {
  const _UserDevice({required this.id, required this.name, this.platform = '', this.added = 0, this.lastUsed = 0, this.passwordDueAt = 0, this.state = 'active', this.thisDevice = false, this.removedBy});
  

@override final  String id;
@override final  String name;
/// `mac`, `windows`, `ios`, `android`.
@override@JsonKey() final  String platform;
/// Seconds since the Unix epoch; 0 when not known.
@override@JsonKey() final  int added;
@override@JsonKey() final  int lastUsed;
@override@JsonKey() final  int passwordDueAt;
/// `active`, `removed` (by an administrator) or `signed_out`.
@override@JsonKey() final  String state;
/// The device of this session.
@override@JsonKey() final  bool thisDevice;
/// `user:<admin>` who removed it.
@override final  String? removedBy;

/// Create a copy of UserDevice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserDeviceCopyWith<_UserDevice> get copyWith => __$UserDeviceCopyWithImpl<_UserDevice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserDevice&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.added, added) || other.added == added)&&(identical(other.lastUsed, lastUsed) || other.lastUsed == lastUsed)&&(identical(other.passwordDueAt, passwordDueAt) || other.passwordDueAt == passwordDueAt)&&(identical(other.state, state) || other.state == state)&&(identical(other.thisDevice, thisDevice) || other.thisDevice == thisDevice)&&(identical(other.removedBy, removedBy) || other.removedBy == removedBy));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,platform,added,lastUsed,passwordDueAt,state,thisDevice,removedBy);
}

@override
String toString() {
    return 'UserDevice(id: $id, name: $name, platform: $platform, added: $added, lastUsed: $lastUsed, passwordDueAt: $passwordDueAt, state: $state, thisDevice: $thisDevice, removedBy: $removedBy)';
}


}

/// @nodoc
abstract mixin class _$UserDeviceCopyWith<$Res> implements $UserDeviceCopyWith<$Res> {
  factory _$UserDeviceCopyWith(_UserDevice value, $Res Function(_UserDevice) _then) = __$UserDeviceCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String platform, int added, int lastUsed, int passwordDueAt, String state, bool thisDevice, String? removedBy
});




}
/// @nodoc
class __$UserDeviceCopyWithImpl<$Res>
    implements _$UserDeviceCopyWith<$Res> {
  __$UserDeviceCopyWithImpl(this._self, this._then);

  final _UserDevice _self;
  final $Res Function(_UserDevice) _then;

/// Create a copy of UserDevice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? platform = null,Object? added = null,Object? lastUsed = null,Object? passwordDueAt = null,Object? state = null,Object? thisDevice = null,Object? removedBy = freezed,}) {
  return _then(_UserDevice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,passwordDueAt: null == passwordDueAt ? _self.passwordDueAt : passwordDueAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,thisDevice: null == thisDevice ? _self.thisDevice : thisDevice // ignore: cast_nullable_to_non_nullable
as bool,removedBy: freezed == removedBy ? _self.removedBy : removedBy // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
