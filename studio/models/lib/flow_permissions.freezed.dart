// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_permissions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowPermissions {

/// `maxperm`, given on the wire as a code (`3`) or a name (`"write"`,
/// 0.2.32); null when the definition names none.
 Perm? get maxperm;
/// Create a copy of FlowPermissions
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowPermissionsCopyWith<FlowPermissions> get copyWith => _$FlowPermissionsCopyWithImpl<FlowPermissions>(this as FlowPermissions, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FlowPermissions;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowPermissions&&(identical(other.maxperm, _this.maxperm) || other.maxperm == _this.maxperm));
}


@override
int get hashCode {
  final _this = this as FlowPermissions;
  return Object.hash(runtimeType,_this.maxperm);
}

@override
String toString() {
  final _this = this as FlowPermissions;
  return 'FlowPermissions(maxperm: ${_this.maxperm})';
}


}

/// @nodoc
abstract mixin class $FlowPermissionsCopyWith<$Res>  {
  factory $FlowPermissionsCopyWith(FlowPermissions value, $Res Function(FlowPermissions) _then) = _$FlowPermissionsCopyWithImpl;
@useResult
$Res call({
 Perm? maxperm
});




}
/// @nodoc
class _$FlowPermissionsCopyWithImpl<$Res>
    implements $FlowPermissionsCopyWith<$Res> {
  _$FlowPermissionsCopyWithImpl(this._self, this._then);

  final FlowPermissions _self;
  final $Res Function(FlowPermissions) _then;

/// Create a copy of FlowPermissions
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? maxperm = freezed,}) {
  return _then(FlowPermissions(
maxperm: freezed == maxperm ? _self.maxperm : maxperm // ignore: cast_nullable_to_non_nullable
as Perm?,
  ));
}

}



/// @nodoc


class _FlowPermissions implements FlowPermissions {
  const _FlowPermissions({this.maxperm});
  

/// `maxperm`, given on the wire as a code (`3`) or a name (`"write"`,
/// 0.2.32); null when the definition names none.
@override final  Perm? maxperm;

/// Create a copy of FlowPermissions
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowPermissionsCopyWith<_FlowPermissions> get copyWith => __$FlowPermissionsCopyWithImpl<_FlowPermissions>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowPermissions&&(identical(other.maxperm, maxperm) || other.maxperm == maxperm));
}


@override
int get hashCode {
    return Object.hash(runtimeType,maxperm);
}

@override
String toString() {
    return 'FlowPermissions(maxperm: $maxperm)';
}


}

/// @nodoc
abstract mixin class _$FlowPermissionsCopyWith<$Res> implements $FlowPermissionsCopyWith<$Res> {
  factory _$FlowPermissionsCopyWith(_FlowPermissions value, $Res Function(_FlowPermissions) _then) = __$FlowPermissionsCopyWithImpl;
@override @useResult
$Res call({
 Perm? maxperm
});




}
/// @nodoc
class __$FlowPermissionsCopyWithImpl<$Res>
    implements _$FlowPermissionsCopyWith<$Res> {
  __$FlowPermissionsCopyWithImpl(this._self, this._then);

  final _FlowPermissions _self;
  final $Res Function(_FlowPermissions) _then;

/// Create a copy of FlowPermissions
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? maxperm = freezed,}) {
  return _then(_FlowPermissions(
maxperm: freezed == maxperm ? _self.maxperm : maxperm // ignore: cast_nullable_to_non_nullable
as Perm?,
  ));
}


}

// dart format on
