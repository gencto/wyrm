// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'requested_right.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RequestedRight {

 String get what; String get detail;
/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RequestedRightCopyWith<RequestedRight> get copyWith => _$RequestedRightCopyWithImpl<RequestedRight>(this as RequestedRight, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RequestedRight;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestedRight&&(identical(other.what, _this.what) || other.what == _this.what)&&(identical(other.detail, _this.detail) || other.detail == _this.detail));
}


@override
int get hashCode {
  final _this = this as RequestedRight;
  return Object.hash(runtimeType,_this.what,_this.detail);
}

@override
String toString() {
  final _this = this as RequestedRight;
  return 'RequestedRight(what: ${_this.what}, detail: ${_this.detail})';
}


}

/// @nodoc
abstract mixin class $RequestedRightCopyWith<$Res>  {
  factory $RequestedRightCopyWith(RequestedRight value, $Res Function(RequestedRight) _then) = _$RequestedRightCopyWithImpl;
@useResult
$Res call({
 String what, String detail
});




}
/// @nodoc
class _$RequestedRightCopyWithImpl<$Res>
    implements $RequestedRightCopyWith<$Res> {
  _$RequestedRightCopyWithImpl(this._self, this._then);

  final RequestedRight _self;
  final $Res Function(RequestedRight) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? what = null,Object? detail = null,}) {
  return _then(RequestedRight(
what: null == what ? _self.what : what // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _RequestedRight implements RequestedRight {
  const _RequestedRight({required this.what, required this.detail});
  

@override final  String what;
@override final  String detail;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RequestedRightCopyWith<_RequestedRight> get copyWith => __$RequestedRightCopyWithImpl<_RequestedRight>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RequestedRight&&(identical(other.what, what) || other.what == what)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,what,detail);
}

@override
String toString() {
    return 'RequestedRight(what: $what, detail: $detail)';
}


}

/// @nodoc
abstract mixin class _$RequestedRightCopyWith<$Res> implements $RequestedRightCopyWith<$Res> {
  factory _$RequestedRightCopyWith(_RequestedRight value, $Res Function(_RequestedRight) _then) = __$RequestedRightCopyWithImpl;
@override @useResult
$Res call({
 String what, String detail
});




}
/// @nodoc
class __$RequestedRightCopyWithImpl<$Res>
    implements _$RequestedRightCopyWith<$Res> {
  __$RequestedRightCopyWithImpl(this._self, this._then);

  final _RequestedRight _self;
  final $Res Function(_RequestedRight) _then;

/// Create a copy of RequestedRight
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? what = null,Object? detail = null,}) {
  return _then(_RequestedRight(
what: null == what ? _self.what : what // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
