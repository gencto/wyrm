// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'install_target.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InstallTarget {

 String get site;/// Its `sys/distribution` (`linux-aarch64`), when read. Whether the
/// user may install on it is the rights check's, from the grants of
/// now (selector `installTargetReason`), not kept here.
 String? get host;
/// Create a copy of InstallTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallTargetCopyWith<InstallTarget> get copyWith => _$InstallTargetCopyWithImpl<InstallTarget>(this as InstallTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InstallTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallTarget&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.host, _this.host) || other.host == _this.host));
}


@override
int get hashCode {
  final _this = this as InstallTarget;
  return Object.hash(runtimeType,_this.site,_this.host);
}

@override
String toString() {
  final _this = this as InstallTarget;
  return 'InstallTarget(site: ${_this.site}, host: ${_this.host})';
}


}

/// @nodoc
abstract mixin class $InstallTargetCopyWith<$Res>  {
  factory $InstallTargetCopyWith(InstallTarget value, $Res Function(InstallTarget) _then) = _$InstallTargetCopyWithImpl;
@useResult
$Res call({
 String site, String? host
});




}
/// @nodoc
class _$InstallTargetCopyWithImpl<$Res>
    implements $InstallTargetCopyWith<$Res> {
  _$InstallTargetCopyWithImpl(this._self, this._then);

  final InstallTarget _self;
  final $Res Function(InstallTarget) _then;

/// Create a copy of InstallTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? host = freezed,}) {
  return _then(InstallTarget(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,host: freezed == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _InstallTarget implements InstallTarget {
  const _InstallTarget({required this.site, this.host});
  

@override final  String site;
/// Its `sys/distribution` (`linux-aarch64`), when read. Whether the
/// user may install on it is the rights check's, from the grants of
/// now (selector `installTargetReason`), not kept here.
@override final  String? host;

/// Create a copy of InstallTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InstallTargetCopyWith<_InstallTarget> get copyWith => __$InstallTargetCopyWithImpl<_InstallTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InstallTarget&&(identical(other.site, site) || other.site == site)&&(identical(other.host, host) || other.host == host));
}


@override
int get hashCode {
    return Object.hash(runtimeType,site,host);
}

@override
String toString() {
    return 'InstallTarget(site: $site, host: $host)';
}


}

/// @nodoc
abstract mixin class _$InstallTargetCopyWith<$Res> implements $InstallTargetCopyWith<$Res> {
  factory _$InstallTargetCopyWith(_InstallTarget value, $Res Function(_InstallTarget) _then) = __$InstallTargetCopyWithImpl;
@override @useResult
$Res call({
 String site, String? host
});




}
/// @nodoc
class __$InstallTargetCopyWithImpl<$Res>
    implements _$InstallTargetCopyWith<$Res> {
  __$InstallTargetCopyWithImpl(this._self, this._then);

  final _InstallTarget _self;
  final $Res Function(_InstallTarget) _then;

/// Create a copy of InstallTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? host = freezed,}) {
  return _then(_InstallTarget(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,host: freezed == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
