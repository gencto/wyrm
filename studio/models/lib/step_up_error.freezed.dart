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


class StepUpRefused implements StepUpError {
  const StepUpRefused(this.said);
  

 final  String said;

/// Create a copy of StepUpError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepUpRefusedCopyWith<StepUpRefused> get copyWith => _$StepUpRefusedCopyWithImpl<StepUpRefused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StepUpRefused&&(identical(other.said, said) || other.said == said));
}


@override
int get hashCode {
    return Object.hash(runtimeType,said);
}

@override
String toString() {
    return 'StepUpError.refused(said: $said)';
}


}

/// @nodoc
abstract mixin class $StepUpRefusedCopyWith<$Res> implements $StepUpErrorCopyWith<$Res> {
  factory $StepUpRefusedCopyWith(StepUpRefused value, $Res Function(StepUpRefused) _then) = _$StepUpRefusedCopyWithImpl;
@useResult
$Res call({
 String said
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
@pragma('vm:prefer-inline') $Res call({Object? said = null,}) {
  return _then(StepUpRefused(
null == said ? _self.said : said // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
