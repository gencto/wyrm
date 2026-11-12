// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_check.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageCheck {

 String get title; String get detail;/// `ok`, `failed` or `skipped`.
 String get result;
/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageCheckCopyWith<PackageCheck> get copyWith => _$PackageCheckCopyWithImpl<PackageCheck>(this as PackageCheck, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageCheck&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as PackageCheck;
  return Object.hash(runtimeType,_this.title,_this.detail,_this.result);
}

@override
String toString() {
  final _this = this as PackageCheck;
  return 'PackageCheck(title: ${_this.title}, detail: ${_this.detail}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $PackageCheckCopyWith<$Res>  {
  factory $PackageCheckCopyWith(PackageCheck value, $Res Function(PackageCheck) _then) = _$PackageCheckCopyWithImpl;
@useResult
$Res call({
 String title, String detail, String result
});




}
/// @nodoc
class _$PackageCheckCopyWithImpl<$Res>
    implements $PackageCheckCopyWith<$Res> {
  _$PackageCheckCopyWithImpl(this._self, this._then);

  final PackageCheck _self;
  final $Res Function(PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? detail = null,Object? result = null,}) {
  return _then(PackageCheck(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _PackageCheck implements PackageCheck {
  const _PackageCheck({required this.title, this.detail = '', this.result = 'ok'});
  

@override final  String title;
@override@JsonKey() final  String detail;
/// `ok`, `failed` or `skipped`.
@override@JsonKey() final  String result;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageCheckCopyWith<_PackageCheck> get copyWith => __$PackageCheckCopyWithImpl<_PackageCheck>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageCheck&&(identical(other.title, title) || other.title == title)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,detail,result);
}

@override
String toString() {
    return 'PackageCheck(title: $title, detail: $detail, result: $result)';
}


}

/// @nodoc
abstract mixin class _$PackageCheckCopyWith<$Res> implements $PackageCheckCopyWith<$Res> {
  factory _$PackageCheckCopyWith(_PackageCheck value, $Res Function(_PackageCheck) _then) = __$PackageCheckCopyWithImpl;
@override @useResult
$Res call({
 String title, String detail, String result
});




}
/// @nodoc
class __$PackageCheckCopyWithImpl<$Res>
    implements _$PackageCheckCopyWith<$Res> {
  __$PackageCheckCopyWithImpl(this._self, this._then);

  final _PackageCheck _self;
  final $Res Function(_PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? detail = null,Object? result = null,}) {
  return _then(_PackageCheck(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
