// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'profile_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProfileInfo {

/// `<vendor>:<model>`.
 String get name;/// The points its `~meta` lists; null when it could not be read.
 int? get points;
/// Create a copy of ProfileInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileInfoCopyWith<ProfileInfo> get copyWith => _$ProfileInfoCopyWithImpl<ProfileInfo>(this as ProfileInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.points, _this.points) || other.points == _this.points));
}


@override
int get hashCode {
  final _this = this as ProfileInfo;
  return Object.hash(runtimeType,_this.name,_this.points);
}

@override
String toString() {
  final _this = this as ProfileInfo;
  return 'ProfileInfo(name: ${_this.name}, points: ${_this.points})';
}


}

/// @nodoc
abstract mixin class $ProfileInfoCopyWith<$Res>  {
  factory $ProfileInfoCopyWith(ProfileInfo value, $Res Function(ProfileInfo) _then) = _$ProfileInfoCopyWithImpl;
@useResult
$Res call({
 String name, int? points
});




}
/// @nodoc
class _$ProfileInfoCopyWithImpl<$Res>
    implements $ProfileInfoCopyWith<$Res> {
  _$ProfileInfoCopyWithImpl(this._self, this._then);

  final ProfileInfo _self;
  final $Res Function(ProfileInfo) _then;

/// Create a copy of ProfileInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? points = freezed,}) {
  return _then(ProfileInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,points: freezed == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}



/// @nodoc


class _ProfileInfo implements ProfileInfo {
  const _ProfileInfo({required this.name, this.points});
  

/// `<vendor>:<model>`.
@override final  String name;
/// The points its `~meta` lists; null when it could not be read.
@override final  int? points;

/// Create a copy of ProfileInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileInfoCopyWith<_ProfileInfo> get copyWith => __$ProfileInfoCopyWithImpl<_ProfileInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.points, points) || other.points == points));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,points);
}

@override
String toString() {
    return 'ProfileInfo(name: $name, points: $points)';
}


}

/// @nodoc
abstract mixin class _$ProfileInfoCopyWith<$Res> implements $ProfileInfoCopyWith<$Res> {
  factory _$ProfileInfoCopyWith(_ProfileInfo value, $Res Function(_ProfileInfo) _then) = __$ProfileInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, int? points
});




}
/// @nodoc
class __$ProfileInfoCopyWithImpl<$Res>
    implements _$ProfileInfoCopyWith<$Res> {
  __$ProfileInfoCopyWithImpl(this._self, this._then);

  final _ProfileInfo _self;
  final $Res Function(_ProfileInfo) _then;

/// Create a copy of ProfileInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? points = freezed,}) {
  return _then(_ProfileInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,points: freezed == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
