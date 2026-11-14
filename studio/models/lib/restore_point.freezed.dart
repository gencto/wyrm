// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'restore_point.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RestorePoint {

/// Unix seconds.
 int get at;/// The version the link ran; empty for a point taken before a restore
/// from a backup.
 String get version;/// Bytes.
 int get size;
/// Create a copy of RestorePoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestorePointCopyWith<RestorePoint> get copyWith => _$RestorePointCopyWithImpl<RestorePoint>(this as RestorePoint, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RestorePoint;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestorePoint&&(identical(other.at, _this.at) || other.at == _this.at)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.size, _this.size) || other.size == _this.size));
}


@override
int get hashCode {
  final _this = this as RestorePoint;
  return Object.hash(runtimeType,_this.at,_this.version,_this.size);
}

@override
String toString() {
  final _this = this as RestorePoint;
  return 'RestorePoint(at: ${_this.at}, version: ${_this.version}, size: ${_this.size})';
}


}

/// @nodoc
abstract mixin class $RestorePointCopyWith<$Res>  {
  factory $RestorePointCopyWith(RestorePoint value, $Res Function(RestorePoint) _then) = _$RestorePointCopyWithImpl;
@useResult
$Res call({
 int at, String version, int size
});




}
/// @nodoc
class _$RestorePointCopyWithImpl<$Res>
    implements $RestorePointCopyWith<$Res> {
  _$RestorePointCopyWithImpl(this._self, this._then);

  final RestorePoint _self;
  final $Res Function(RestorePoint) _then;

/// Create a copy of RestorePoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? at = null,Object? version = null,Object? size = null,}) {
  return _then(RestorePoint(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _RestorePoint implements RestorePoint {
  const _RestorePoint({this.at = 0, this.version = '', this.size = 0});
  

/// Unix seconds.
@override@JsonKey() final  int at;
/// The version the link ran; empty for a point taken before a restore
/// from a backup.
@override@JsonKey() final  String version;
/// Bytes.
@override@JsonKey() final  int size;

/// Create a copy of RestorePoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestorePointCopyWith<_RestorePoint> get copyWith => __$RestorePointCopyWithImpl<_RestorePoint>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestorePoint&&(identical(other.at, at) || other.at == at)&&(identical(other.version, version) || other.version == version)&&(identical(other.size, size) || other.size == size));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at,version,size);
}

@override
String toString() {
    return 'RestorePoint(at: $at, version: $version, size: $size)';
}


}

/// @nodoc
abstract mixin class _$RestorePointCopyWith<$Res> implements $RestorePointCopyWith<$Res> {
  factory _$RestorePointCopyWith(_RestorePoint value, $Res Function(_RestorePoint) _then) = __$RestorePointCopyWithImpl;
@override @useResult
$Res call({
 int at, String version, int size
});




}
/// @nodoc
class __$RestorePointCopyWithImpl<$Res>
    implements _$RestorePointCopyWith<$Res> {
  __$RestorePointCopyWithImpl(this._self, this._then);

  final _RestorePoint _self;
  final $Res Function(_RestorePoint) _then;

/// Create a copy of RestorePoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? at = null,Object? version = null,Object? size = null,}) {
  return _then(_RestorePoint(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
