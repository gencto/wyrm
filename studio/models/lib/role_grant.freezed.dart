// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'role_grant.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RoleGrant {

/// The role or subject (`operator`, `link:modbus`).
 String get subject;/// A key pattern (`wy/{site}/downstream/**`).
 String get path;/// An access level; for a rule of the ACL, its messages and flows.
 GrantLevel get level;/// Where it comes from (a row from a source this client does not know
/// is refused at decode: its level could not be read).
 GrantSource get source;
/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoleGrantCopyWith<RoleGrant> get copyWith => _$RoleGrantCopyWithImpl<RoleGrant>(this as RoleGrant, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RoleGrant;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoleGrant&&(identical(other.subject, _this.subject) || other.subject == _this.subject)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.source, _this.source) || other.source == _this.source));
}


@override
int get hashCode {
  final _this = this as RoleGrant;
  return Object.hash(runtimeType,_this.subject,_this.path,_this.level,_this.source);
}

@override
String toString() {
  final _this = this as RoleGrant;
  return 'RoleGrant(subject: ${_this.subject}, path: ${_this.path}, level: ${_this.level}, source: ${_this.source})';
}


}

/// @nodoc
abstract mixin class $RoleGrantCopyWith<$Res>  {
  factory $RoleGrantCopyWith(RoleGrant value, $Res Function(RoleGrant) _then) = _$RoleGrantCopyWithImpl;
@useResult
$Res call({
 String subject, String path, GrantLevel level, GrantSource source
});


$GrantLevelCopyWith<$Res> get level;

}
/// @nodoc
class _$RoleGrantCopyWithImpl<$Res>
    implements $RoleGrantCopyWith<$Res> {
  _$RoleGrantCopyWithImpl(this._self, this._then);

  final RoleGrant _self;
  final $Res Function(RoleGrant) _then;

/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subject = null,Object? path = null,Object? level = null,Object? source = null,}) {
  return _then(RoleGrant(
subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as GrantLevel,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as GrantSource,
  ));
}
/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GrantLevelCopyWith<$Res> get level {
  
  return $GrantLevelCopyWith<$Res>(_self.level, (value) {
    return _then(_self.copyWith(level: value));
  });
}
}



/// @nodoc


class _RoleGrant implements RoleGrant {
  const _RoleGrant({required this.subject, required this.path, required this.level, required this.source});
  

/// The role or subject (`operator`, `link:modbus`).
@override final  String subject;
/// A key pattern (`wy/{site}/downstream/**`).
@override final  String path;
/// An access level; for a rule of the ACL, its messages and flows.
@override final  GrantLevel level;
/// Where it comes from (a row from a source this client does not know
/// is refused at decode: its level could not be read).
@override final  GrantSource source;

/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoleGrantCopyWith<_RoleGrant> get copyWith => __$RoleGrantCopyWithImpl<_RoleGrant>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoleGrant&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.path, path) || other.path == path)&&(identical(other.level, level) || other.level == level)&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode {
    return Object.hash(runtimeType,subject,path,level,source);
}

@override
String toString() {
    return 'RoleGrant(subject: $subject, path: $path, level: $level, source: $source)';
}


}

/// @nodoc
abstract mixin class _$RoleGrantCopyWith<$Res> implements $RoleGrantCopyWith<$Res> {
  factory _$RoleGrantCopyWith(_RoleGrant value, $Res Function(_RoleGrant) _then) = __$RoleGrantCopyWithImpl;
@override @useResult
$Res call({
 String subject, String path, GrantLevel level, GrantSource source
});


@override $GrantLevelCopyWith<$Res> get level;

}
/// @nodoc
class __$RoleGrantCopyWithImpl<$Res>
    implements _$RoleGrantCopyWith<$Res> {
  __$RoleGrantCopyWithImpl(this._self, this._then);

  final _RoleGrant _self;
  final $Res Function(_RoleGrant) _then;

/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subject = null,Object? path = null,Object? level = null,Object? source = null,}) {
  return _then(_RoleGrant(
subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as GrantLevel,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as GrantSource,
  ));
}

/// Create a copy of RoleGrant
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GrantLevelCopyWith<$Res> get level {
  
  return $GrantLevelCopyWith<$Res>(_self.level, (value) {
    return _then(_self.copyWith(level: value));
  });
}
}

// dart format on
