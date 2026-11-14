// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step_up_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepUpRequest {

/// What is being applied, in order.
 IList<StepUpLine> get lines;/// The device key or the password is being checked.
 bool get busy;/// Confirmed: the request goes again.
 bool get done;/// The last try failed: `bad_password`, a cancelled prompt, …
 String? get error;/// The session has no device key here, or it stopped working: the
/// password is the only way.
 bool get passwordOnly;
/// Create a copy of StepUpRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpRequestCopyWith<StepUpRequest> get copyWith => _$StepUpRequestCopyWithImpl<StepUpRequest>(this as StepUpRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StepUpRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpRequest&&const DeepCollectionEquality().equals(other.lines, _this.lines)&&(identical(other.busy, _this.busy) || other.busy == _this.busy)&&(identical(other.done, _this.done) || other.done == _this.done)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.passwordOnly, _this.passwordOnly) || other.passwordOnly == _this.passwordOnly));
}


@override
int get hashCode {
  final _this = this as StepUpRequest;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.lines),_this.busy,_this.done,_this.error,_this.passwordOnly);
}

@override
String toString() {
  final _this = this as StepUpRequest;
  return 'StepUpRequest(lines: ${_this.lines}, busy: ${_this.busy}, done: ${_this.done}, error: ${_this.error}, passwordOnly: ${_this.passwordOnly})';
}


}

/// @nodoc
abstract mixin class $StepUpRequestCopyWith<$Res>  {
  factory $StepUpRequestCopyWith(StepUpRequest value, $Res Function(StepUpRequest) _then) = _$StepUpRequestCopyWithImpl;
@useResult
$Res call({
 IList<StepUpLine> lines, bool busy, bool done, String? error, bool passwordOnly
});




}
/// @nodoc
class _$StepUpRequestCopyWithImpl<$Res>
    implements $StepUpRequestCopyWith<$Res> {
  _$StepUpRequestCopyWithImpl(this._self, this._then);

  final StepUpRequest _self;
  final $Res Function(StepUpRequest) _then;

/// Create a copy of StepUpRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lines = null,Object? busy = null,Object? done = null,Object? error = freezed,Object? passwordOnly = null,}) {
  return _then(StepUpRequest(
lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as IList<StepUpLine>,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,passwordOnly: null == passwordOnly ? _self.passwordOnly : passwordOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _StepUpRequest implements StepUpRequest {
  const _StepUpRequest({this.lines = const IListConst([]), this.busy = false, this.done = false, this.error, this.passwordOnly = false});
  

/// What is being applied, in order.
@override@JsonKey() final  IList<StepUpLine> lines;
/// The device key or the password is being checked.
@override@JsonKey() final  bool busy;
/// Confirmed: the request goes again.
@override@JsonKey() final  bool done;
/// The last try failed: `bad_password`, a cancelled prompt, …
@override final  String? error;
/// The session has no device key here, or it stopped working: the
/// password is the only way.
@override@JsonKey() final  bool passwordOnly;

/// Create a copy of StepUpRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepUpRequestCopyWith<_StepUpRequest> get copyWith => __$StepUpRequestCopyWithImpl<_StepUpRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StepUpRequest&&const DeepCollectionEquality().equals(other.lines, lines)&&(identical(other.busy, busy) || other.busy == busy)&&(identical(other.done, done) || other.done == done)&&(identical(other.error, error) || other.error == error)&&(identical(other.passwordOnly, passwordOnly) || other.passwordOnly == passwordOnly));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(lines),busy,done,error,passwordOnly);
}

@override
String toString() {
    return 'StepUpRequest(lines: $lines, busy: $busy, done: $done, error: $error, passwordOnly: $passwordOnly)';
}


}

/// @nodoc
abstract mixin class _$StepUpRequestCopyWith<$Res> implements $StepUpRequestCopyWith<$Res> {
  factory _$StepUpRequestCopyWith(_StepUpRequest value, $Res Function(_StepUpRequest) _then) = __$StepUpRequestCopyWithImpl;
@override @useResult
$Res call({
 IList<StepUpLine> lines, bool busy, bool done, String? error, bool passwordOnly
});




}
/// @nodoc
class __$StepUpRequestCopyWithImpl<$Res>
    implements _$StepUpRequestCopyWith<$Res> {
  __$StepUpRequestCopyWithImpl(this._self, this._then);

  final _StepUpRequest _self;
  final $Res Function(_StepUpRequest) _then;

/// Create a copy of StepUpRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lines = null,Object? busy = null,Object? done = null,Object? error = freezed,Object? passwordOnly = null,}) {
  return _then(_StepUpRequest(
lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as IList<StepUpLine>,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,done: null == done ? _self.done : done // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,passwordOnly: null == passwordOnly ? _self.passwordOnly : passwordOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
