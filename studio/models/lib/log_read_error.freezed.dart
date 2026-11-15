// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'log_read_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LogReadError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LogReadError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LogReadError()';
}


}

/// @nodoc
class $LogReadErrorCopyWith<$Res>  {
$LogReadErrorCopyWith(LogReadError _, $Res Function(LogReadError) __);
}



/// @nodoc


class LogRefused implements LogReadError {
  const LogRefused(this.status, this.message);
  

 final  String status;
 final  String message;

/// Create a copy of LogReadError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LogRefusedCopyWith<LogRefused> get copyWith => _$LogRefusedCopyWithImpl<LogRefused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LogRefused&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,message);
}

@override
String toString() {
    return 'LogReadError.refused(status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $LogRefusedCopyWith<$Res> implements $LogReadErrorCopyWith<$Res> {
  factory $LogRefusedCopyWith(LogRefused value, $Res Function(LogRefused) _then) = _$LogRefusedCopyWithImpl;
@useResult
$Res call({
 String status, String message
});




}
/// @nodoc
class _$LogRefusedCopyWithImpl<$Res>
    implements $LogRefusedCopyWith<$Res> {
  _$LogRefusedCopyWithImpl(this._self, this._then);

  final LogRefused _self;
  final $Res Function(LogRefused) _then;

/// Create a copy of LogReadError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = null,}) {
  return _then(LogRefused(
null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LogInvalid implements LogReadError {
  const LogInvalid(this.field, this.reason);
  

 final  String field;
 final  String reason;

/// Create a copy of LogReadError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LogInvalidCopyWith<LogInvalid> get copyWith => _$LogInvalidCopyWithImpl<LogInvalid>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LogInvalid&&(identical(other.field, field) || other.field == field)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,reason);
}

@override
String toString() {
    return 'LogReadError.invalid(field: $field, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $LogInvalidCopyWith<$Res> implements $LogReadErrorCopyWith<$Res> {
  factory $LogInvalidCopyWith(LogInvalid value, $Res Function(LogInvalid) _then) = _$LogInvalidCopyWithImpl;
@useResult
$Res call({
 String field, String reason
});




}
/// @nodoc
class _$LogInvalidCopyWithImpl<$Res>
    implements $LogInvalidCopyWith<$Res> {
  _$LogInvalidCopyWithImpl(this._self, this._then);

  final LogInvalid _self;
  final $Res Function(LogInvalid) _then;

/// Create a copy of LogReadError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field = null,Object? reason = null,}) {
  return _then(LogInvalid(
null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
