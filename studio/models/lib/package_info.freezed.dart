// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'package_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PackageInfo {

 String get name; String get version;/// `process` or `wasm`.
 String get kind; String? get source; String? get sha256;
/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PackageInfoCopyWith<PackageInfo> get copyWith => _$PackageInfoCopyWithImpl<PackageInfo>(this as PackageInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PackageInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PackageInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256));
}


@override
int get hashCode {
  final _this = this as PackageInfo;
  return Object.hash(runtimeType,_this.name,_this.version,_this.kind,_this.source,_this.sha256);
}

@override
String toString() {
  final _this = this as PackageInfo;
  return 'PackageInfo(name: ${_this.name}, version: ${_this.version}, kind: ${_this.kind}, source: ${_this.source}, sha256: ${_this.sha256})';
}


}

/// @nodoc
abstract mixin class $PackageInfoCopyWith<$Res>  {
  factory $PackageInfoCopyWith(PackageInfo value, $Res Function(PackageInfo) _then) = _$PackageInfoCopyWithImpl;
@useResult
$Res call({
 String name, String version, String kind, String? source, String? sha256
});




}
/// @nodoc
class _$PackageInfoCopyWithImpl<$Res>
    implements $PackageInfoCopyWith<$Res> {
  _$PackageInfoCopyWithImpl(this._self, this._then);

  final PackageInfo _self;
  final $Res Function(PackageInfo) _then;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? version = null,Object? kind = null,Object? source = freezed,Object? sha256 = freezed,}) {
  return _then(PackageInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _PackageInfo implements PackageInfo {
  const _PackageInfo({required this.name, this.version = '', this.kind = 'process', this.source, this.sha256});
  

@override final  String name;
@override@JsonKey() final  String version;
/// `process` or `wasm`.
@override@JsonKey() final  String kind;
@override final  String? source;
@override final  String? sha256;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PackageInfoCopyWith<_PackageInfo> get copyWith => __$PackageInfoCopyWithImpl<_PackageInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PackageInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.source, source) || other.source == source)&&(identical(other.sha256, sha256) || other.sha256 == sha256));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,version,kind,source,sha256);
}

@override
String toString() {
    return 'PackageInfo(name: $name, version: $version, kind: $kind, source: $source, sha256: $sha256)';
}


}

/// @nodoc
abstract mixin class _$PackageInfoCopyWith<$Res> implements $PackageInfoCopyWith<$Res> {
  factory _$PackageInfoCopyWith(_PackageInfo value, $Res Function(_PackageInfo) _then) = __$PackageInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, String version, String kind, String? source, String? sha256
});




}
/// @nodoc
class __$PackageInfoCopyWithImpl<$Res>
    implements _$PackageInfoCopyWith<$Res> {
  __$PackageInfoCopyWithImpl(this._self, this._then);

  final _PackageInfo _self;
  final $Res Function(_PackageInfo) _then;

/// Create a copy of PackageInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = null,Object? kind = null,Object? source = freezed,Object? sha256 = freezed,}) {
  return _then(_PackageInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
