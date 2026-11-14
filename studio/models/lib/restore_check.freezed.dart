// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'restore_check.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RestoreCheck {

 String get site; bool get sameSite; String get created; String get broker;/// `none`, `passphrase` or `broker`.
 String get sealed;/// Store SCHEMA by store: `(backup, here)`.
 IMap<String, (int, int,)> get schemas;/// The sections of the file with their bytes.
 IMap<String, int> get sections;/// `none`, `same`, `differ` or `other`.
 String get keys;/// The key files that are not this broker's.
 IList<String> get keysDiffer; bool get controlOpensHere;/// Each link of the file: `new` or `exists`.
 IMap<String, String> get links;/// Each blocks `replace`.
 IList<String> get problems; IList<String> get notes;
/// Create a copy of RestoreCheck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestoreCheckCopyWith<RestoreCheck> get copyWith => _$RestoreCheckCopyWithImpl<RestoreCheck>(this as RestoreCheck, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RestoreCheck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreCheck&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.sameSite, _this.sameSite) || other.sameSite == _this.sameSite)&&(identical(other.created, _this.created) || other.created == _this.created)&&(identical(other.broker, _this.broker) || other.broker == _this.broker)&&(identical(other.sealed, _this.sealed) || other.sealed == _this.sealed)&&(identical(other.schemas, _this.schemas) || other.schemas == _this.schemas)&&(identical(other.sections, _this.sections) || other.sections == _this.sections)&&(identical(other.keys, _this.keys) || other.keys == _this.keys)&&const DeepCollectionEquality().equals(other.keysDiffer, _this.keysDiffer)&&(identical(other.controlOpensHere, _this.controlOpensHere) || other.controlOpensHere == _this.controlOpensHere)&&(identical(other.links, _this.links) || other.links == _this.links)&&const DeepCollectionEquality().equals(other.problems, _this.problems)&&const DeepCollectionEquality().equals(other.notes, _this.notes));
}


@override
int get hashCode {
  final _this = this as RestoreCheck;
  return Object.hash(runtimeType,_this.site,_this.sameSite,_this.created,_this.broker,_this.sealed,_this.schemas,_this.sections,_this.keys,const DeepCollectionEquality().hash(_this.keysDiffer),_this.controlOpensHere,_this.links,const DeepCollectionEquality().hash(_this.problems),const DeepCollectionEquality().hash(_this.notes));
}

@override
String toString() {
  final _this = this as RestoreCheck;
  return 'RestoreCheck(site: ${_this.site}, sameSite: ${_this.sameSite}, created: ${_this.created}, broker: ${_this.broker}, sealed: ${_this.sealed}, schemas: ${_this.schemas}, sections: ${_this.sections}, keys: ${_this.keys}, keysDiffer: ${_this.keysDiffer}, controlOpensHere: ${_this.controlOpensHere}, links: ${_this.links}, problems: ${_this.problems}, notes: ${_this.notes})';
}


}

/// @nodoc
abstract mixin class $RestoreCheckCopyWith<$Res>  {
  factory $RestoreCheckCopyWith(RestoreCheck value, $Res Function(RestoreCheck) _then) = _$RestoreCheckCopyWithImpl;
@useResult
$Res call({
 String site, bool sameSite, String created, String broker, String sealed, IMap<String, (int, int,)> schemas, IMap<String, int> sections, String keys, IList<String> keysDiffer, bool controlOpensHere, IMap<String, String> links, IList<String> problems, IList<String> notes
});




}
/// @nodoc
class _$RestoreCheckCopyWithImpl<$Res>
    implements $RestoreCheckCopyWith<$Res> {
  _$RestoreCheckCopyWithImpl(this._self, this._then);

  final RestoreCheck _self;
  final $Res Function(RestoreCheck) _then;

/// Create a copy of RestoreCheck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? sameSite = null,Object? created = null,Object? broker = null,Object? sealed = null,Object? schemas = null,Object? sections = null,Object? keys = null,Object? keysDiffer = null,Object? controlOpensHere = null,Object? links = null,Object? problems = null,Object? notes = null,}) {
  return _then(RestoreCheck(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,sameSite: null == sameSite ? _self.sameSite : sameSite // ignore: cast_nullable_to_non_nullable
as bool,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as String,broker: null == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as String,schemas: null == schemas ? _self.schemas : schemas // ignore: cast_nullable_to_non_nullable
as IMap<String, (int, int,)>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,keys: null == keys ? _self.keys : keys // ignore: cast_nullable_to_non_nullable
as String,keysDiffer: null == keysDiffer ? _self.keysDiffer : keysDiffer // ignore: cast_nullable_to_non_nullable
as IList<String>,controlOpensHere: null == controlOpensHere ? _self.controlOpensHere : controlOpensHere // ignore: cast_nullable_to_non_nullable
as bool,links: null == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}

}



/// @nodoc


class _RestoreCheck implements RestoreCheck {
  const _RestoreCheck({this.site = '', this.sameSite = false, this.created = '', this.broker = '', this.sealed = 'none', this.schemas = const IMapConst({}), this.sections = const IMapConst({}), this.keys = 'none', this.keysDiffer = const IListConst([]), this.controlOpensHere = true, this.links = const IMapConst({}), this.problems = const IListConst([]), this.notes = const IListConst([])});
  

@override@JsonKey() final  String site;
@override@JsonKey() final  bool sameSite;
@override@JsonKey() final  String created;
@override@JsonKey() final  String broker;
/// `none`, `passphrase` or `broker`.
@override@JsonKey() final  String sealed;
/// Store SCHEMA by store: `(backup, here)`.
@override@JsonKey() final  IMap<String, (int, int,)> schemas;
/// The sections of the file with their bytes.
@override@JsonKey() final  IMap<String, int> sections;
/// `none`, `same`, `differ` or `other`.
@override@JsonKey() final  String keys;
/// The key files that are not this broker's.
@override@JsonKey() final  IList<String> keysDiffer;
@override@JsonKey() final  bool controlOpensHere;
/// Each link of the file: `new` or `exists`.
@override@JsonKey() final  IMap<String, String> links;
/// Each blocks `replace`.
@override@JsonKey() final  IList<String> problems;
@override@JsonKey() final  IList<String> notes;

/// Create a copy of RestoreCheck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RestoreCheckCopyWith<_RestoreCheck> get copyWith => __$RestoreCheckCopyWithImpl<_RestoreCheck>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RestoreCheck&&(identical(other.site, site) || other.site == site)&&(identical(other.sameSite, sameSite) || other.sameSite == sameSite)&&(identical(other.created, created) || other.created == created)&&(identical(other.broker, broker) || other.broker == broker)&&(identical(other.sealed, sealed) || other.sealed == sealed)&&(identical(other.schemas, schemas) || other.schemas == schemas)&&(identical(other.sections, sections) || other.sections == sections)&&(identical(other.keys, keys) || other.keys == keys)&&const DeepCollectionEquality().equals(other.keysDiffer, keysDiffer)&&(identical(other.controlOpensHere, controlOpensHere) || other.controlOpensHere == controlOpensHere)&&(identical(other.links, links) || other.links == links)&&const DeepCollectionEquality().equals(other.problems, problems)&&const DeepCollectionEquality().equals(other.notes, notes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,site,sameSite,created,broker,sealed,schemas,sections,keys,const DeepCollectionEquality().hash(keysDiffer),controlOpensHere,links,const DeepCollectionEquality().hash(problems),const DeepCollectionEquality().hash(notes));
}

@override
String toString() {
    return 'RestoreCheck(site: $site, sameSite: $sameSite, created: $created, broker: $broker, sealed: $sealed, schemas: $schemas, sections: $sections, keys: $keys, keysDiffer: $keysDiffer, controlOpensHere: $controlOpensHere, links: $links, problems: $problems, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$RestoreCheckCopyWith<$Res> implements $RestoreCheckCopyWith<$Res> {
  factory _$RestoreCheckCopyWith(_RestoreCheck value, $Res Function(_RestoreCheck) _then) = __$RestoreCheckCopyWithImpl;
@override @useResult
$Res call({
 String site, bool sameSite, String created, String broker, String sealed, IMap<String, (int, int,)> schemas, IMap<String, int> sections, String keys, IList<String> keysDiffer, bool controlOpensHere, IMap<String, String> links, IList<String> problems, IList<String> notes
});




}
/// @nodoc
class __$RestoreCheckCopyWithImpl<$Res>
    implements _$RestoreCheckCopyWith<$Res> {
  __$RestoreCheckCopyWithImpl(this._self, this._then);

  final _RestoreCheck _self;
  final $Res Function(_RestoreCheck) _then;

/// Create a copy of RestoreCheck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? sameSite = null,Object? created = null,Object? broker = null,Object? sealed = null,Object? schemas = null,Object? sections = null,Object? keys = null,Object? keysDiffer = null,Object? controlOpensHere = null,Object? links = null,Object? problems = null,Object? notes = null,}) {
  return _then(_RestoreCheck(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,sameSite: null == sameSite ? _self.sameSite : sameSite // ignore: cast_nullable_to_non_nullable
as bool,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as String,broker: null == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String,sealed: null == sealed ? _self.sealed : sealed // ignore: cast_nullable_to_non_nullable
as String,schemas: null == schemas ? _self.schemas : schemas // ignore: cast_nullable_to_non_nullable
as IMap<String, (int, int,)>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,keys: null == keys ? _self.keys : keys // ignore: cast_nullable_to_non_nullable
as String,keysDiffer: null == keysDiffer ? _self.keysDiffer : keysDiffer // ignore: cast_nullable_to_non_nullable
as IList<String>,controlOpensHere: null == controlOpensHere ? _self.controlOpensHere : controlOpensHere // ignore: cast_nullable_to_non_nullable
as bool,links: null == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,problems: null == problems ? _self.problems : problems // ignore: cast_nullable_to_non_nullable
as IList<String>,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as IList<String>,
  ));
}


}

// dart format on
