// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'link_revision.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkRevision {

 int get rev;/// The parameters as indented JSON (secrets are sealed, not here).
 String get params;
/// Create a copy of LinkRevision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkRevisionCopyWith<LinkRevision> get copyWith => _$LinkRevisionCopyWithImpl<LinkRevision>(this as LinkRevision, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkRevision&&(identical(other.rev, rev) || other.rev == rev)&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode => Object.hash(runtimeType,rev,params);

@override
String toString() {
  return 'LinkRevision(rev: $rev, params: $params)';
}


}

/// @nodoc
abstract mixin class $LinkRevisionCopyWith<$Res>  {
  factory $LinkRevisionCopyWith(LinkRevision value, $Res Function(LinkRevision) _then) = _$LinkRevisionCopyWithImpl;
@useResult
$Res call({
 int rev, String params
});




}
/// @nodoc
class _$LinkRevisionCopyWithImpl<$Res>
    implements $LinkRevisionCopyWith<$Res> {
  _$LinkRevisionCopyWithImpl(this._self, this._then);

  final LinkRevision _self;
  final $Res Function(LinkRevision) _then;

/// Create a copy of LinkRevision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rev = null,Object? params = null,}) {
  return _then(_self.copyWith(
rev: null == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _LinkRevision implements LinkRevision {
  const _LinkRevision({required this.rev, required this.params});
  

@override final  int rev;
/// The parameters as indented JSON (secrets are sealed, not here).
@override final  String params;

/// Create a copy of LinkRevision
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinkRevisionCopyWith<_LinkRevision> get copyWith => __$LinkRevisionCopyWithImpl<_LinkRevision>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinkRevision&&(identical(other.rev, rev) || other.rev == rev)&&(identical(other.params, params) || other.params == params));
}


@override
int get hashCode => Object.hash(runtimeType,rev,params);

@override
String toString() {
  return 'LinkRevision(rev: $rev, params: $params)';
}


}

/// @nodoc
abstract mixin class _$LinkRevisionCopyWith<$Res> implements $LinkRevisionCopyWith<$Res> {
  factory _$LinkRevisionCopyWith(_LinkRevision value, $Res Function(_LinkRevision) _then) = __$LinkRevisionCopyWithImpl;
@override @useResult
$Res call({
 int rev, String params
});




}
/// @nodoc
class __$LinkRevisionCopyWithImpl<$Res>
    implements _$LinkRevisionCopyWith<$Res> {
  __$LinkRevisionCopyWithImpl(this._self, this._then);

  final _LinkRevision _self;
  final $Res Function(_LinkRevision) _then;

/// Create a copy of LinkRevision
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rev = null,Object? params = null,}) {
  return _then(_LinkRevision(
rev: null == rev ? _self.rev : rev // ignore: cast_nullable_to_non_nullable
as int,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
