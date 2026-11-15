// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lock_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LockError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LockError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LockError()';
}


}

/// @nodoc
class $LockErrorCopyWith<$Res>  {
$LockErrorCopyWith(LockError _, $Res Function(LockError) __);
}



/// @nodoc


class LockErrorWrongPassword implements LockError {
  const LockErrorWrongPassword();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LockErrorWrongPassword);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LockError.wrongPassword()';
}


}




/// @nodoc


class LockErrorRefused implements LockError {
  const LockErrorRefused(this.said);
  

 final  String said;

/// Create a copy of LockError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LockErrorRefusedCopyWith<LockErrorRefused> get copyWith => _$LockErrorRefusedCopyWithImpl<LockErrorRefused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LockErrorRefused&&(identical(other.said, said) || other.said == said));
}


@override
int get hashCode {
    return Object.hash(runtimeType,said);
}

@override
String toString() {
    return 'LockError.refused(said: $said)';
}


}

/// @nodoc
abstract mixin class $LockErrorRefusedCopyWith<$Res> implements $LockErrorCopyWith<$Res> {
  factory $LockErrorRefusedCopyWith(LockErrorRefused value, $Res Function(LockErrorRefused) _then) = _$LockErrorRefusedCopyWithImpl;
@useResult
$Res call({
 String said
});




}
/// @nodoc
class _$LockErrorRefusedCopyWithImpl<$Res>
    implements $LockErrorRefusedCopyWith<$Res> {
  _$LockErrorRefusedCopyWithImpl(this._self, this._then);

  final LockErrorRefused _self;
  final $Res Function(LockErrorRefused) _then;

/// Create a copy of LockError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? said = null,}) {
  return _then(LockErrorRefused(
null == said ? _self.said : said // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
