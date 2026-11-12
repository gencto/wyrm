// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'login_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LoginState {

 String? get password; String? get gateway; String? get user; int get step; IList<String> get recent; IMap<String, int> get probes; bool get remember; LoginFailure? get failure; String? get reason; int get preload; IList<int> get preloadLate;
/// Create a copy of LoginState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoginStateCopyWith<LoginState> get copyWith => _$LoginStateCopyWithImpl<LoginState>(this as LoginState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LoginState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoginState&&(identical(other.password, _this.password) || other.password == _this.password)&&(identical(other.gateway, _this.gateway) || other.gateway == _this.gateway)&&(identical(other.user, _this.user) || other.user == _this.user)&&(identical(other.step, _this.step) || other.step == _this.step)&&const DeepCollectionEquality().equals(other.recent, _this.recent)&&(identical(other.probes, _this.probes) || other.probes == _this.probes)&&(identical(other.remember, _this.remember) || other.remember == _this.remember)&&(identical(other.failure, _this.failure) || other.failure == _this.failure)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.preload, _this.preload) || other.preload == _this.preload)&&const DeepCollectionEquality().equals(other.preloadLate, _this.preloadLate));
}


@override
int get hashCode {
  final _this = this as LoginState;
  return Object.hash(runtimeType,_this.password,_this.gateway,_this.user,_this.step,const DeepCollectionEquality().hash(_this.recent),_this.probes,_this.remember,_this.failure,_this.reason,_this.preload,const DeepCollectionEquality().hash(_this.preloadLate));
}

@override
String toString() {
  final _this = this as LoginState;
  return 'LoginState(password: ${_this.password}, gateway: ${_this.gateway}, user: ${_this.user}, step: ${_this.step}, recent: ${_this.recent}, probes: ${_this.probes}, remember: ${_this.remember}, failure: ${_this.failure}, reason: ${_this.reason}, preload: ${_this.preload}, preloadLate: ${_this.preloadLate})';
}


}

/// @nodoc
abstract mixin class $LoginStateCopyWith<$Res>  {
  factory $LoginStateCopyWith(LoginState value, $Res Function(LoginState) _then) = _$LoginStateCopyWithImpl;
@useResult
$Res call({
 String? password, String? gateway, String? user, int step, IList<String> recent, IMap<String, int> probes, bool remember, LoginFailure? failure, String? reason, int preload, IList<int> preloadLate
});




}
/// @nodoc
class _$LoginStateCopyWithImpl<$Res>
    implements $LoginStateCopyWith<$Res> {
  _$LoginStateCopyWithImpl(this._self, this._then);

  final LoginState _self;
  final $Res Function(LoginState) _then;

/// Create a copy of LoginState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? password = freezed,Object? gateway = freezed,Object? user = freezed,Object? step = null,Object? recent = null,Object? probes = null,Object? remember = null,Object? failure = freezed,Object? reason = freezed,Object? preload = null,Object? preloadLate = null,}) {
  return _then(LoginState(
password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,recent: null == recent ? _self.recent : recent // ignore: cast_nullable_to_non_nullable
as IList<String>,probes: null == probes ? _self.probes : probes // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,remember: null == remember ? _self.remember : remember // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as LoginFailure?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,preload: null == preload ? _self.preload : preload // ignore: cast_nullable_to_non_nullable
as int,preloadLate: null == preloadLate ? _self.preloadLate : preloadLate // ignore: cast_nullable_to_non_nullable
as IList<int>,
  ));
}

}



/// @nodoc


class _LoginState implements LoginState {
  const _LoginState({this.password, this.gateway, this.user, this.step = 0, this.recent = const IListConst([]), this.probes = const IMapConst({}), this.remember = true, this.failure, this.reason, this.preload = 0, this.preloadLate = const IListConst([])});
  

@override final  String? password;
@override final  String? gateway;
@override final  String? user;
@override@JsonKey() final  int step;
@override@JsonKey() final  IList<String> recent;
@override@JsonKey() final  IMap<String, int> probes;
@override@JsonKey() final  bool remember;
@override final  LoginFailure? failure;
@override final  String? reason;
@override@JsonKey() final  int preload;
@override@JsonKey() final  IList<int> preloadLate;

/// Create a copy of LoginState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoginStateCopyWith<_LoginState> get copyWith => __$LoginStateCopyWithImpl<_LoginState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoginState&&(identical(other.password, password) || other.password == password)&&(identical(other.gateway, gateway) || other.gateway == gateway)&&(identical(other.user, user) || other.user == user)&&(identical(other.step, step) || other.step == step)&&const DeepCollectionEquality().equals(other.recent, recent)&&(identical(other.probes, probes) || other.probes == probes)&&(identical(other.remember, remember) || other.remember == remember)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.preload, preload) || other.preload == preload)&&const DeepCollectionEquality().equals(other.preloadLate, preloadLate));
}


@override
int get hashCode {
    return Object.hash(runtimeType,password,gateway,user,step,const DeepCollectionEquality().hash(recent),probes,remember,failure,reason,preload,const DeepCollectionEquality().hash(preloadLate));
}

@override
String toString() {
    return 'LoginState(password: $password, gateway: $gateway, user: $user, step: $step, recent: $recent, probes: $probes, remember: $remember, failure: $failure, reason: $reason, preload: $preload, preloadLate: $preloadLate)';
}


}

/// @nodoc
abstract mixin class _$LoginStateCopyWith<$Res> implements $LoginStateCopyWith<$Res> {
  factory _$LoginStateCopyWith(_LoginState value, $Res Function(_LoginState) _then) = __$LoginStateCopyWithImpl;
@override @useResult
$Res call({
 String? password, String? gateway, String? user, int step, IList<String> recent, IMap<String, int> probes, bool remember, LoginFailure? failure, String? reason, int preload, IList<int> preloadLate
});




}
/// @nodoc
class __$LoginStateCopyWithImpl<$Res>
    implements _$LoginStateCopyWith<$Res> {
  __$LoginStateCopyWithImpl(this._self, this._then);

  final _LoginState _self;
  final $Res Function(_LoginState) _then;

/// Create a copy of LoginState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? password = freezed,Object? gateway = freezed,Object? user = freezed,Object? step = null,Object? recent = null,Object? probes = null,Object? remember = null,Object? failure = freezed,Object? reason = freezed,Object? preload = null,Object? preloadLate = null,}) {
  return _then(_LoginState(
password: freezed == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String?,gateway: freezed == gateway ? _self.gateway : gateway // ignore: cast_nullable_to_non_nullable
as String?,user: freezed == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String?,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,recent: null == recent ? _self.recent : recent // ignore: cast_nullable_to_non_nullable
as IList<String>,probes: null == probes ? _self.probes : probes // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,remember: null == remember ? _self.remember : remember // ignore: cast_nullable_to_non_nullable
as bool,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as LoginFailure?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,preload: null == preload ? _self.preload : preload // ignore: cast_nullable_to_non_nullable
as int,preloadLate: null == preloadLate ? _self.preloadLate : preloadLate // ignore: cast_nullable_to_non_nullable
as IList<int>,
  ));
}


}

// dart format on
