// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'action_answer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ActionAnswer {

 bool get success; String? get message;
/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActionAnswerCopyWith<ActionAnswer> get copyWith => _$ActionAnswerCopyWithImpl<ActionAnswer>(this as ActionAnswer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActionAnswer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActionAnswer&&(identical(other.success, _this.success) || other.success == _this.success)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ActionAnswer;
  return Object.hash(runtimeType,_this.success,_this.message);
}

@override
String toString() {
  final _this = this as ActionAnswer;
  return 'ActionAnswer(success: ${_this.success}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $ActionAnswerCopyWith<$Res>  {
  factory $ActionAnswerCopyWith(ActionAnswer value, $Res Function(ActionAnswer) _then) = _$ActionAnswerCopyWithImpl;
@useResult
$Res call({
 bool success, String? message
});




}
/// @nodoc
class _$ActionAnswerCopyWithImpl<$Res>
    implements $ActionAnswerCopyWith<$Res> {
  _$ActionAnswerCopyWithImpl(this._self, this._then);

  final ActionAnswer _self;
  final $Res Function(ActionAnswer) _then;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? success = null,Object? message = freezed,}) {
  return _then(ActionAnswer(
success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _ActionAnswer implements ActionAnswer {
  const _ActionAnswer({required this.success, this.message});
  

@override final  bool success;
@override final  String? message;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActionAnswerCopyWith<_ActionAnswer> get copyWith => __$ActionAnswerCopyWithImpl<_ActionAnswer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActionAnswer&&(identical(other.success, success) || other.success == success)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,success,message);
}

@override
String toString() {
    return 'ActionAnswer(success: $success, message: $message)';
}


}

/// @nodoc
abstract mixin class _$ActionAnswerCopyWith<$Res> implements $ActionAnswerCopyWith<$Res> {
  factory _$ActionAnswerCopyWith(_ActionAnswer value, $Res Function(_ActionAnswer) _then) = __$ActionAnswerCopyWithImpl;
@override @useResult
$Res call({
 bool success, String? message
});




}
/// @nodoc
class __$ActionAnswerCopyWithImpl<$Res>
    implements _$ActionAnswerCopyWith<$Res> {
  __$ActionAnswerCopyWithImpl(this._self, this._then);

  final _ActionAnswer _self;
  final $Res Function(_ActionAnswer) _then;

/// Create a copy of ActionAnswer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? success = null,Object? message = freezed,}) {
  return _then(_ActionAnswer(
success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
