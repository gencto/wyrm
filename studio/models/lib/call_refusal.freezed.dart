// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'call_refusal.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CallRefusal {

/// The status by its wire name (`permission_denied`).
 String get status;/// The broker's words, as they came; empty when it sent none.
 String get message;/// The key the call was made on, when the screen names it.
 String? get key;
/// Create a copy of CallRefusal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CallRefusalCopyWith<CallRefusal> get copyWith => _$CallRefusalCopyWithImpl<CallRefusal>(this as CallRefusal, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CallRefusal;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CallRefusal&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.key, _this.key) || other.key == _this.key));
}


@override
int get hashCode {
  final _this = this as CallRefusal;
  return Object.hash(runtimeType,_this.status,_this.message,_this.key);
}

@override
String toString() {
  final _this = this as CallRefusal;
  return 'CallRefusal(status: ${_this.status}, message: ${_this.message}, key: ${_this.key})';
}


}

/// @nodoc
abstract mixin class $CallRefusalCopyWith<$Res>  {
  factory $CallRefusalCopyWith(CallRefusal value, $Res Function(CallRefusal) _then) = _$CallRefusalCopyWithImpl;
@useResult
$Res call({
 String status, String message, String? key
});




}
/// @nodoc
class _$CallRefusalCopyWithImpl<$Res>
    implements $CallRefusalCopyWith<$Res> {
  _$CallRefusalCopyWithImpl(this._self, this._then);

  final CallRefusal _self;
  final $Res Function(CallRefusal) _then;

/// Create a copy of CallRefusal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? message = null,Object? key = freezed,}) {
  return _then(CallRefusal(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _CallRefusal implements CallRefusal {
  const _CallRefusal({required this.status, this.message = '', this.key});
  

/// The status by its wire name (`permission_denied`).
@override final  String status;
/// The broker's words, as they came; empty when it sent none.
@override@JsonKey() final  String message;
/// The key the call was made on, when the screen names it.
@override final  String? key;

/// Create a copy of CallRefusal
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CallRefusalCopyWith<_CallRefusal> get copyWith => __$CallRefusalCopyWithImpl<_CallRefusal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CallRefusal&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,message,key);
}

@override
String toString() {
    return 'CallRefusal(status: $status, message: $message, key: $key)';
}


}

/// @nodoc
abstract mixin class _$CallRefusalCopyWith<$Res> implements $CallRefusalCopyWith<$Res> {
  factory _$CallRefusalCopyWith(_CallRefusal value, $Res Function(_CallRefusal) _then) = __$CallRefusalCopyWithImpl;
@override @useResult
$Res call({
 String status, String message, String? key
});




}
/// @nodoc
class __$CallRefusalCopyWithImpl<$Res>
    implements _$CallRefusalCopyWith<$Res> {
  __$CallRefusalCopyWithImpl(this._self, this._then);

  final _CallRefusal _self;
  final $Res Function(_CallRefusal) _then;

/// Create a copy of CallRefusal
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = null,Object? key = freezed,}) {
  return _then(_CallRefusal(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
