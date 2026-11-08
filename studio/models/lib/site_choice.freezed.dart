// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'site_choice.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SiteChoice {

 String get site;/// `this`, `downstream` or `upstream`.
 String get relation;/// The site it is reached through, when not directly.
 String? get via;
/// Create a copy of SiteChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SiteChoiceCopyWith<SiteChoice> get copyWith => _$SiteChoiceCopyWithImpl<SiteChoice>(this as SiteChoice, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SiteChoice&&(identical(other.site, site) || other.site == site)&&(identical(other.relation, relation) || other.relation == relation)&&(identical(other.via, via) || other.via == via));
}


@override
int get hashCode => Object.hash(runtimeType,site,relation,via);

@override
String toString() {
  return 'SiteChoice(site: $site, relation: $relation, via: $via)';
}


}

/// @nodoc
abstract mixin class $SiteChoiceCopyWith<$Res>  {
  factory $SiteChoiceCopyWith(SiteChoice value, $Res Function(SiteChoice) _then) = _$SiteChoiceCopyWithImpl;
@useResult
$Res call({
 String site, String relation, String? via
});




}
/// @nodoc
class _$SiteChoiceCopyWithImpl<$Res>
    implements $SiteChoiceCopyWith<$Res> {
  _$SiteChoiceCopyWithImpl(this._self, this._then);

  final SiteChoice _self;
  final $Res Function(SiteChoice) _then;

/// Create a copy of SiteChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? relation = null,Object? via = freezed,}) {
  return _then(_self.copyWith(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,relation: null == relation ? _self.relation : relation // ignore: cast_nullable_to_non_nullable
as String,via: freezed == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _SiteChoice implements SiteChoice {
  const _SiteChoice({required this.site, this.relation = 'this', this.via});
  

@override final  String site;
/// `this`, `downstream` or `upstream`.
@override@JsonKey() final  String relation;
/// The site it is reached through, when not directly.
@override final  String? via;

/// Create a copy of SiteChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SiteChoiceCopyWith<_SiteChoice> get copyWith => __$SiteChoiceCopyWithImpl<_SiteChoice>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SiteChoice&&(identical(other.site, site) || other.site == site)&&(identical(other.relation, relation) || other.relation == relation)&&(identical(other.via, via) || other.via == via));
}


@override
int get hashCode => Object.hash(runtimeType,site,relation,via);

@override
String toString() {
  return 'SiteChoice(site: $site, relation: $relation, via: $via)';
}


}

/// @nodoc
abstract mixin class _$SiteChoiceCopyWith<$Res> implements $SiteChoiceCopyWith<$Res> {
  factory _$SiteChoiceCopyWith(_SiteChoice value, $Res Function(_SiteChoice) _then) = __$SiteChoiceCopyWithImpl;
@override @useResult
$Res call({
 String site, String relation, String? via
});




}
/// @nodoc
class __$SiteChoiceCopyWithImpl<$Res>
    implements _$SiteChoiceCopyWith<$Res> {
  __$SiteChoiceCopyWithImpl(this._self, this._then);

  final _SiteChoice _self;
  final $Res Function(_SiteChoice) _then;

/// Create a copy of SiteChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? relation = null,Object? via = freezed,}) {
  return _then(_SiteChoice(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,relation: null == relation ? _self.relation : relation // ignore: cast_nullable_to_non_nullable
as String,via: freezed == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
