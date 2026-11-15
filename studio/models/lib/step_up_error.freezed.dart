// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step_up_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepUpError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpError()';
}


}

/// @nodoc
class $StepUpErrorCopyWith<$Res>  {
$StepUpErrorCopyWith(StepUpError _, $Res Function(StepUpError) __);
}



/// @nodoc


class StepUpWrongPassword implements StepUpError {
  const StepUpWrongPassword();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpWrongPassword);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpError.wrongPassword()';
}


}




/// @nodoc


class StepUpStopped implements StepUpError {
  const StepUpStopped();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpStopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpError.stopped()';
}


}




/// @nodoc


class StepUpKeyGone implements StepUpError {
  const StepUpKeyGone();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpKeyGone);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StepUpError.keyGone()';
}


}




/// @nodoc


class StepUpGateway implements StepUpError {
  const StepUpGateway(this.code);
  

 final  RefusalCode code;

/// Create a copy of StepUpError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpGatewayCopyWith<StepUpGateway> get copyWith => _$StepUpGatewayCopyWithImpl<StepUpGateway>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpGateway&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code);
}

@override
String toString() {
    return 'StepUpError.gateway(code: $code)';
}


}

/// @nodoc
abstract mixin class $StepUpGatewayCopyWith<$Res> implements $StepUpErrorCopyWith<$Res> {
  factory $StepUpGatewayCopyWith(StepUpGateway value, $Res Function(StepUpGateway) _then) = _$StepUpGatewayCopyWithImpl;
@useResult
$Res call({
 RefusalCode code
});




}
/// @nodoc
class _$StepUpGatewayCopyWithImpl<$Res>
    implements $StepUpGatewayCopyWith<$Res> {
  _$StepUpGatewayCopyWithImpl(this._self, this._then);

  final StepUpGateway _self;
  final $Res Function(StepUpGateway) _then;

/// Create a copy of StepUpError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,}) {
  return _then(StepUpGateway(
null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as RefusalCode,
  ));
}


}

/// @nodoc


class StepUpRefused implements StepUpError {
  const StepUpRefused(this.message);
  

 final  String message;

/// Create a copy of StepUpError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpRefusedCopyWith<StepUpRefused> get copyWith => _$StepUpRefusedCopyWithImpl<StepUpRefused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpRefused&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'StepUpError.refused(message: $message)';
}


}

/// @nodoc
abstract mixin class $StepUpRefusedCopyWith<$Res> implements $StepUpErrorCopyWith<$Res> {
  factory $StepUpRefusedCopyWith(StepUpRefused value, $Res Function(StepUpRefused) _then) = _$StepUpRefusedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$StepUpRefusedCopyWithImpl<$Res>
    implements $StepUpRefusedCopyWith<$Res> {
  _$StepUpRefusedCopyWithImpl(this._self, this._then);

  final StepUpRefused _self;
  final $Res Function(StepUpRefused) _then;

/// Create a copy of StepUpError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(StepUpRefused(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
