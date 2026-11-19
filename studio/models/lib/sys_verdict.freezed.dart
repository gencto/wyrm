// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sys_verdict.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SysVerdict {

 bool get success; String? get message;/// The status of a refusal by its wire name (`timeout`), when the call
/// was refused instead of answered; the screen writes it before the
/// message.
 String? get status;
/// Create a copy of SysVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SysVerdictCopyWith<SysVerdict> get copyWith => _$SysVerdictCopyWithImpl<SysVerdict>(this as SysVerdict, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SysVerdict;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SysVerdict&&(identical(other.success, _this.success) || other.success == _this.success)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as SysVerdict;
  return Object.hash(runtimeType,_this.success,_this.message,_this.status);
}

@override
String toString() {
  final _this = this as SysVerdict;
  return 'SysVerdict(success: ${_this.success}, message: ${_this.message}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $SysVerdictCopyWith<$Res>  {
  factory $SysVerdictCopyWith(SysVerdict value, $Res Function(SysVerdict) _then) = _$SysVerdictCopyWithImpl;
@useResult
$Res call({
 bool success, String? message, String? status
});




}
/// @nodoc
class _$SysVerdictCopyWithImpl<$Res>
    implements $SysVerdictCopyWith<$Res> {
  _$SysVerdictCopyWithImpl(this._self, this._then);

  final SysVerdict _self;
  final $Res Function(SysVerdict) _then;

/// Create a copy of SysVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? success = null,Object? message = freezed,Object? status = freezed,}) {
  return _then(SysVerdict(
success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _SysVerdict implements SysVerdict {
  const _SysVerdict({required this.success, this.message, this.status});
  

@override final  bool success;
@override final  String? message;
/// The status of a refusal by its wire name (`timeout`), when the call
/// was refused instead of answered; the screen writes it before the
/// message.
@override final  String? status;

/// Create a copy of SysVerdict
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SysVerdictCopyWith<_SysVerdict> get copyWith => __$SysVerdictCopyWithImpl<_SysVerdict>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SysVerdict&&(identical(other.success, success) || other.success == success)&&(identical(other.message, message) || other.message == message)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,success,message,status);
}

@override
String toString() {
    return 'SysVerdict(success: $success, message: $message, status: $status)';
}


}

/// @nodoc
abstract mixin class _$SysVerdictCopyWith<$Res> implements $SysVerdictCopyWith<$Res> {
  factory _$SysVerdictCopyWith(_SysVerdict value, $Res Function(_SysVerdict) _then) = __$SysVerdictCopyWithImpl;
@override @useResult
$Res call({
 bool success, String? message, String? status
});




}
/// @nodoc
class __$SysVerdictCopyWithImpl<$Res>
    implements _$SysVerdictCopyWith<$Res> {
  __$SysVerdictCopyWithImpl(this._self, this._then);

  final _SysVerdict _self;
  final $Res Function(_SysVerdict) _then;

/// Create a copy of SysVerdict
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? success = null,Object? message = freezed,Object? status = freezed,}) {
  return _then(_SysVerdict(
success: null == success ? _self.success : success // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
