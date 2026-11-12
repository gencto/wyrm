// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'grant.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Grant {

/// A key or a pattern with `*` and `**` (`wy/**`).
 String get key;/// `none`, `list`, `read`, `write` or `config`.
 String get level;
/// Create a copy of Grant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GrantCopyWith<Grant> get copyWith => _$GrantCopyWithImpl<Grant>(this as Grant, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Grant;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Grant&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.level, _this.level) || other.level == _this.level));
}


@override
int get hashCode {
  final _this = this as Grant;
  return Object.hash(runtimeType,_this.key,_this.level);
}

@override
String toString() {
  final _this = this as Grant;
  return 'Grant(key: ${_this.key}, level: ${_this.level})';
}


}

/// @nodoc
abstract mixin class $GrantCopyWith<$Res>  {
  factory $GrantCopyWith(Grant value, $Res Function(Grant) _then) = _$GrantCopyWithImpl;
@useResult
$Res call({
 String key, String level
});




}
/// @nodoc
class _$GrantCopyWithImpl<$Res>
    implements $GrantCopyWith<$Res> {
  _$GrantCopyWithImpl(this._self, this._then);

  final Grant _self;
  final $Res Function(Grant) _then;

/// Create a copy of Grant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? level = null,}) {
  return _then(Grant(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _Grant implements Grant {
  const _Grant({required this.key, required this.level});
  

/// A key or a pattern with `*` and `**` (`wy/**`).
@override final  String key;
/// `none`, `list`, `read`, `write` or `config`.
@override final  String level;

/// Create a copy of Grant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GrantCopyWith<_Grant> get copyWith => __$GrantCopyWithImpl<_Grant>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Grant&&(identical(other.key, key) || other.key == key)&&(identical(other.level, level) || other.level == level));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,level);
}

@override
String toString() {
    return 'Grant(key: $key, level: $level)';
}


}

/// @nodoc
abstract mixin class _$GrantCopyWith<$Res> implements $GrantCopyWith<$Res> {
  factory _$GrantCopyWith(_Grant value, $Res Function(_Grant) _then) = __$GrantCopyWithImpl;
@override @useResult
$Res call({
 String key, String level
});




}
/// @nodoc
class __$GrantCopyWithImpl<$Res>
    implements _$GrantCopyWith<$Res> {
  __$GrantCopyWithImpl(this._self, this._then);

  final _Grant _self;
  final $Res Function(_Grant) _then;

/// Create a copy of Grant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? level = null,}) {
  return _then(_Grant(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
