// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'site_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SiteState {

 String? get gateway; String? get user; String? get name; String? get role; bool get connected; String? get current; IList<Grant> get grants; IList<SiteChoice> get choices; String? get max;
/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SiteStateCopyWith<SiteState> get copyWith => _$SiteStateCopyWithImpl<SiteState>(this as SiteState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SiteState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SiteState&&(identical(other.gateway, _this.gateway) || other.gateway == _this.gateway)&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.connected, _this.connected) || other.connected == _this.connected)&&(identical(other.current, _this.current) || other.current == _this.current)&&const DeepCollectionEquality().equals(other.grants, _this.grants)&&const DeepCollectionEquality().equals(other.choices, _this.choices)&&(identical(other.max, _this.max) || other.max == _this.max));
}


@override
int get hashCode {
  final _this = this as SiteState;
  return Object.hash(runtimeType,_this.gateway,_this.user,_this.name,_this.role,_this.connected,_this.current,const DeepCollectionEquality().hash(_this.grants),const DeepCollectionEquality().hash(_this.choices),_this.max);
}

@override
String toString() {
  final _this = this as SiteState;
  return 'SiteState(gateway: ${_this.gateway}, user: ${_this.user}, name: ${_this.name}, role: ${_this.role}, connected: ${_this.connected}, current: ${_this.current}, grants: ${_this.grants}, choices: ${_this.choices}, max: ${_this.max})';
}


}

/// @nodoc
abstract mixin class $SiteStateCopyWith<$Res>  {
  factory $SiteStateCopyWith(SiteState value, $Res Function(SiteState) _then) = _$SiteStateCopyWithImpl;
@useResult
$Res call({
 String? gateway, String? user, String? name, String? role, bool connected, String? current, IList<Grant> grants, IList<SiteChoice> choices, String? max
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
@pragma('vm:prefer-inline') @override $Res call({Object? gateway = freezed,Object? user = freezed,Object? name = freezed,Object? role = freezed,Object? connected = null,Object? current = freezed,Object? grants = null,Object? choices = null,Object? max = freezed,}) {
  return _then(SiteState(
gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as String?,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<Grant>,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<SiteChoice>,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _SiteState implements SiteState {
  const _SiteState({this.gateway, this.user, this.name, this.role, this.connected = false, this.current, this.grants = const IListConst([]), this.choices = const IListConst([]), this.max});
  

@override final  String? gateway;
@override final  String? user;
@override final  String? name;
@override final  String? role;
@override@JsonKey() final  bool connected;
@override final  String? current;
@override@JsonKey() final  IList<Grant> grants;
@override@JsonKey() final  IList<SiteChoice> choices;
@override final  String? max;

/// Create a copy of SiteState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SiteStateCopyWith<_SiteState> get copyWith => __$SiteStateCopyWithImpl<_SiteState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SiteState&&(identical(other.gateway, gateway) || other.gateway == gateway)&&(identical(other.user, user) || other.user == user)&&(identical(other.name, name) || other.name == name)&&(identical(other.role, role) || other.role == role)&&(identical(other.connected, connected) || other.connected == connected)&&(identical(other.current, current) || other.current == current)&&const DeepCollectionEquality().equals(other.grants, grants)&&const DeepCollectionEquality().equals(other.choices, choices)&&(identical(other.max, max) || other.max == max));
}


@override
int get hashCode {
    return Object.hash(runtimeType,gateway,user,name,role,connected,current,const DeepCollectionEquality().hash(grants),const DeepCollectionEquality().hash(choices),max);
}

@override
String toString() {
    return 'SiteState(gateway: $gateway, user: $user, name: $name, role: $role, connected: $connected, current: $current, grants: $grants, choices: $choices, max: $max)';
}


}

/// @nodoc
abstract mixin class _$SiteStateCopyWith<$Res> implements $SiteStateCopyWith<$Res> {
  factory _$SiteStateCopyWith(_SiteState value, $Res Function(_SiteState) _then) = __$SiteStateCopyWithImpl;
@override @useResult
$Res call({
 String? gateway, String? user, String? name, String? role, bool connected, String? current, IList<Grant> grants, IList<SiteChoice> choices, String? max
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
@override @pragma('vm:prefer-inline') $Res call({Object? gateway = freezed,Object? user = freezed,Object? name = freezed,Object? role = freezed,Object? connected = null,Object? current = freezed,Object? grants = null,Object? choices = null,Object? max = freezed,}) {
  return _then(_SiteState(
gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as String?,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as IList<Grant>,choices: null == choices ? _self.choices : choices // ignore: cast_nullable_to_non_nullable
as IList<SiteChoice>,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
