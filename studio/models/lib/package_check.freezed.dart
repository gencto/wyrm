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

 PackageFinding get finding; PackageCheckResult get result;
/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageCheckCopyWith<PackageCheck> get copyWith => _$PackageCheckCopyWithImpl<PackageCheck>(this as PackageCheck, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageCheck&&(identical(other.finding, _this.finding) || other.finding == _this.finding)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as PackageCheck;
  return Object.hash(runtimeType,_this.finding,_this.result);
}

@override
String toString() {
  final _this = this as PackageCheck;
  return 'PackageCheck(finding: ${_this.finding}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $PackageCheckCopyWith<$Res>  {
  factory $PackageCheckCopyWith(PackageCheck value, $Res Function(PackageCheck) _then) = _$PackageCheckCopyWithImpl;
@useResult
$Res call({
 PackageFinding finding, PackageCheckResult result
});


$PackageFindingCopyWith<$Res> get finding;

}
/// @nodoc
class _$PackageCheckCopyWithImpl<$Res>
    implements $PackageCheckCopyWith<$Res> {
  _$PackageCheckCopyWithImpl(this._self, this._then);

  final PackageCheck _self;
  final $Res Function(PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? finding = null,Object? result = null,}) {
  return _then(PackageCheck(
null == finding ? _self.finding : finding // ignore: cast_nullable_to_non_nullable
as PackageFinding,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as PackageCheckResult,
  ));
}
/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PackageFindingCopyWith<$Res> get finding {
  
  return $PackageFindingCopyWith<$Res>(_self.finding, (value) {
    return _then(_self.copyWith(finding: value));
  });
}
}



/// @nodoc


class _PackageCheck implements PackageCheck {
  const _PackageCheck(this.finding, {this.result = PackageCheckResult.ok});
  

@override final  PackageFinding finding;
@override@JsonKey() final  PackageCheckResult result;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageCheckCopyWith<_PackageCheck> get copyWith => __$PackageCheckCopyWithImpl<_PackageCheck>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageCheck&&(identical(other.finding, finding) || other.finding == finding)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,finding,result);
}

@override
String toString() {
    return 'PackageCheck(finding: $finding, result: $result)';
}


}

/// @nodoc
abstract mixin class _$PackageCheckCopyWith<$Res> implements $PackageCheckCopyWith<$Res> {
  factory _$PackageCheckCopyWith(_PackageCheck value, $Res Function(_PackageCheck) _then) = __$PackageCheckCopyWithImpl;
@override @useResult
$Res call({
 PackageFinding finding, PackageCheckResult result
});


@override $PackageFindingCopyWith<$Res> get finding;

}
/// @nodoc
class __$PackageCheckCopyWithImpl<$Res>
    implements _$PackageCheckCopyWith<$Res> {
  __$PackageCheckCopyWithImpl(this._self, this._then);

  final _PackageCheck _self;
  final $Res Function(_PackageCheck) _then;

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? finding = null,Object? result = null,}) {
  return _then(_PackageCheck(
null == finding ? _self.finding : finding // ignore: cast_nullable_to_non_nullable
as PackageFinding,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as PackageCheckResult,
  ));
}

/// Create a copy of PackageCheck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PackageFindingCopyWith<$Res> get finding {
  
  return $PackageFindingCopyWith<$Res>(_self.finding, (value) {
    return _then(_self.copyWith(finding: value));
  });
}
}

// dart format on
