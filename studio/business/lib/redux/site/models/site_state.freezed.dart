// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'site_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SiteState {

 String? get gateway; String? get user; String? get name; String? get role; bool get connected;
/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SiteStateCopyWith<SiteState> get copyWith => _$SiteStateCopyWithImpl<SiteState>(this as SiteState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SiteState&&(identical(other.gateway, gateway) || other.gateway == gateway)&&(identical(other.user, user) || other.user == user)&&(identical(other.name, name) || other.name == name)&&(identical(other.role, role) || other.role == role)&&(identical(other.connected, connected) || other.connected == connected));
}


@override
int get hashCode => Object.hash(runtimeType,gateway,user,name,role,connected);

@override
String toString() {
  return 'SiteState(gateway: $gateway, user: $user, name: $name, role: $role, connected: $connected)';
}


}

/// @nodoc
abstract mixin class $SiteStateCopyWith<$Res>  {
  factory $SiteStateCopyWith(SiteState value, $Res Function(SiteState) _then) = _$SiteStateCopyWithImpl;
@useResult
$Res call({
 String? gateway, String? user, String? name, String? role, bool connected
});




}
/// @nodoc
class _$SiteStateCopyWithImpl<$Res>
    implements $SiteStateCopyWith<$Res> {
  _$SiteStateCopyWithImpl(this._self, this._then);

  final SiteState _self;
  final $Res Function(SiteState) _then;

/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gateway = freezed,Object? user = freezed,Object? name = freezed,Object? role = freezed,Object? connected = null,}) {
  return _then(_self.copyWith(
gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _SiteState implements SiteState {
  const _SiteState({this.gateway, this.user, this.name, this.role, this.connected = false});
  

@override final  String? gateway;
@override final  String? user;
@override final  String? name;
@override final  String? role;
@override@JsonKey() final  bool connected;

/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SiteStateCopyWith<_SiteState> get copyWith => __$SiteStateCopyWithImpl<_SiteState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SiteState&&(identical(other.gateway, gateway) || other.gateway == gateway)&&(identical(other.user, user) || other.user == user)&&(identical(other.name, name) || other.name == name)&&(identical(other.role, role) || other.role == role)&&(identical(other.connected, connected) || other.connected == connected));
}


@override
int get hashCode => Object.hash(runtimeType,gateway,user,name,role,connected);

@override
String toString() {
  return 'SiteState(gateway: $gateway, user: $user, name: $name, role: $role, connected: $connected)';
}


}

/// @nodoc
abstract mixin class _$SiteStateCopyWith<$Res> implements $SiteStateCopyWith<$Res> {
  factory _$SiteStateCopyWith(_SiteState value, $Res Function(_SiteState) _then) = __$SiteStateCopyWithImpl;
@override @useResult
$Res call({
 String? gateway, String? user, String? name, String? role, bool connected
});




}
/// @nodoc
class __$SiteStateCopyWithImpl<$Res>
    implements _$SiteStateCopyWith<$Res> {
  __$SiteStateCopyWithImpl(this._self, this._then);

  final _SiteState _self;
  final $Res Function(_SiteState) _then;

/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gateway = freezed,Object? user = freezed,Object? name = freezed,Object? role = freezed,Object? connected = null,}) {
  return _then(_SiteState(
gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
