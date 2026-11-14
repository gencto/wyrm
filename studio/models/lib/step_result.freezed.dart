// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepResult {

/// `ok`, `failed` or `skipped`.
 String get status; String get message; DateTime? get time;
/// Create a copy of StepResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepResultCopyWith<StepResult> get copyWith => _$StepResultCopyWithImpl<StepResult>(this as StepResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StepResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepResult&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.time, _this.time) || other.time == _this.time));
}


@override
int get hashCode {
  final _this = this as StepResult;
  return Object.hash(runtimeType,_this.status,_this.message,_this.time);
}

@override
String toString() {
  final _this = this as StepResult;
  return 'StepResult(status: ${_this.status}, message: ${_this.message}, time: ${_this.time})';
}


}

/// @nodoc
abstract mixin class $StepResultCopyWith<$Res>  {
  factory $StepResultCopyWith(StepResult value, $Res Function(StepResult) _then) = _$StepResultCopyWithImpl;
@useResult
$Res call({
 String status, String message, DateTime? time
});




}
/// @nodoc
class _$StepResultCopyWithImpl<$Res>
    implements $StepResultCopyWith<$Res> {
  _$StepResultCopyWithImpl(this._self, this._then);

  final StepResult _self;
  final $Res Function(StepResult) _then;

/// Create a copy of StepResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? message = null,Object? time = freezed,}) {
  return _then(StepResult(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,time: freezed == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}



/// @nodoc


class _StepResult implements StepResult {
  const _StepResult({required this.status, this.message = '', this.time});
  

/// `ok`, `failed` or `skipped`.
@override final  String status;
@override@JsonKey() final  String message;
@override final  DateTime? time;

/// Create a copy of StepResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepResultCopyWith<_StepResult> get copyWith => __$StepResultCopyWithImpl<_StepResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StepResult&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message)&&(identical(other.time, time) || other.time == time));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,message,time);
}

@override
String toString() {
    return 'StepResult(status: $status, message: $message, time: $time)';
}


}

/// @nodoc
abstract mixin class _$StepResultCopyWith<$Res> implements $StepResultCopyWith<$Res> {
  factory _$StepResultCopyWith(_StepResult value, $Res Function(_StepResult) _then) = __$StepResultCopyWithImpl;
@override @useResult
$Res call({
 String status, String message, DateTime? time
});




}
/// @nodoc
class __$StepResultCopyWithImpl<$Res>
    implements _$StepResultCopyWith<$Res> {
  __$StepResultCopyWithImpl(this._self, this._then);

  final _StepResult _self;
  final $Res Function(_StepResult) _then;

/// Create a copy of StepResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = null,Object? time = freezed,}) {
  return _then(_StepResult(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,time: freezed == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
