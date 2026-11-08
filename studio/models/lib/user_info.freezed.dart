// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UserInfo {

 String get name; IList<String> get roles; bool get disabled;
/// Create a copy of UserInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInfoCopyWith<UserInfo> get copyWith => _$UserInfoCopyWithImpl<UserInfo>(this as UserInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInfo&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.roles, roles)&&(identical(other.disabled, disabled) || other.disabled == disabled));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(roles),disabled);

@override
String toString() {
  return 'UserInfo(name: $name, roles: $roles, disabled: $disabled)';
}


}

/// @nodoc
abstract mixin class $UserInfoCopyWith<$Res>  {
  factory $UserInfoCopyWith(UserInfo value, $Res Function(UserInfo) _then) = _$UserInfoCopyWithImpl;
@useResult
$Res call({
 String name, IList<String> roles, bool disabled
});




}
/// @nodoc
class _$UserInfoCopyWithImpl<$Res>
    implements $UserInfoCopyWith<$Res> {
  _$UserInfoCopyWithImpl(this._self, this._then);

  final UserInfo _self;
  final $Res Function(UserInfo) _then;

/// Create a copy of UserInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? roles = null,Object? disabled = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as IList<String>,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _UserInfo implements UserInfo {
  const _UserInfo({required this.name, this.roles = const IListConst([]), this.disabled = false});
  

@override final  String name;
@override@JsonKey() final  IList<String> roles;
@override@JsonKey() final  bool disabled;

/// Create a copy of UserInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserInfoCopyWith<_UserInfo> get copyWith => __$UserInfoCopyWithImpl<_UserInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserInfo&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.roles, roles)&&(identical(other.disabled, disabled) || other.disabled == disabled));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(roles),disabled);

@override
String toString() {
  return 'UserInfo(name: $name, roles: $roles, disabled: $disabled)';
}


}

/// @nodoc
abstract mixin class _$UserInfoCopyWith<$Res> implements $UserInfoCopyWith<$Res> {
  factory _$UserInfoCopyWith(_UserInfo value, $Res Function(_UserInfo) _then) = __$UserInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, IList<String> roles, bool disabled
});




}
/// @nodoc
class __$UserInfoCopyWithImpl<$Res>
    implements _$UserInfoCopyWith<$Res> {
  __$UserInfoCopyWithImpl(this._self, this._then);

  final _UserInfo _self;
  final $Res Function(_UserInfo) _then;

/// Create a copy of UserInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? roles = null,Object? disabled = null,}) {
  return _then(_UserInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as IList<String>,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
