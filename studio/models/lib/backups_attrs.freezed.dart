// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backups_attrs.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupsAttrs {

 bool get exportSecrets; IList<SendLink> get sendLinks; IList<BackupSection> get sections; int get keepDays;
/// Create a copy of BackupsAttrs
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupsAttrsCopyWith<BackupsAttrs> get copyWith => _$BackupsAttrsCopyWithImpl<BackupsAttrs>(this as BackupsAttrs, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BackupsAttrs;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupsAttrs&&(identical(other.exportSecrets, _this.exportSecrets) || other.exportSecrets == _this.exportSecrets)&&const DeepCollectionEquality().equals(other.sendLinks, _this.sendLinks)&&const DeepCollectionEquality().equals(other.sections, _this.sections)&&(identical(other.keepDays, _this.keepDays) || other.keepDays == _this.keepDays));
}


@override
int get hashCode {
  final _this = this as BackupsAttrs;
  return Object.hash(runtimeType,_this.exportSecrets,const DeepCollectionEquality().hash(_this.sendLinks),const DeepCollectionEquality().hash(_this.sections),_this.keepDays);
}

@override
String toString() {
  final _this = this as BackupsAttrs;
  return 'BackupsAttrs(exportSecrets: ${_this.exportSecrets}, sendLinks: ${_this.sendLinks}, sections: ${_this.sections}, keepDays: ${_this.keepDays})';
}


}

/// @nodoc
abstract mixin class $BackupsAttrsCopyWith<$Res>  {
  factory $BackupsAttrsCopyWith(BackupsAttrs value, $Res Function(BackupsAttrs) _then) = _$BackupsAttrsCopyWithImpl;
@useResult
$Res call({
 bool exportSecrets, IList<SendLink> sendLinks, IList<BackupSection> sections, int keepDays
});




}
/// @nodoc
class _$BackupsAttrsCopyWithImpl<$Res>
    implements $BackupsAttrsCopyWith<$Res> {
  _$BackupsAttrsCopyWithImpl(this._self, this._then);

  final BackupsAttrs _self;
  final $Res Function(BackupsAttrs) _then;

/// Create a copy of BackupsAttrs
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? exportSecrets = null,Object? sendLinks = null,Object? sections = null,Object? keepDays = null,}) {
  return _then(BackupsAttrs(
exportSecrets: null == exportSecrets ? _self.exportSecrets : exportSecrets // ignore: cast_nullable_to_non_nullable
as bool,sendLinks: null == sendLinks ? _self.sendLinks : sendLinks // ignore: cast_nullable_to_non_nullable
as IList<SendLink>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,keepDays: null == keepDays ? _self.keepDays : keepDays // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _BackupsAttrs implements BackupsAttrs {
  const _BackupsAttrs({this.exportSecrets = false, this.sendLinks = const IListConst([]), this.sections = const IListConst([]), this.keepDays = 7});
  

@override@JsonKey() final  bool exportSecrets;
@override@JsonKey() final  IList<SendLink> sendLinks;
@override@JsonKey() final  IList<BackupSection> sections;
@override@JsonKey() final  int keepDays;

/// Create a copy of BackupsAttrs
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupsAttrsCopyWith<_BackupsAttrs> get copyWith => __$BackupsAttrsCopyWithImpl<_BackupsAttrs>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupsAttrs&&(identical(other.exportSecrets, exportSecrets) || other.exportSecrets == exportSecrets)&&const DeepCollectionEquality().equals(other.sendLinks, sendLinks)&&const DeepCollectionEquality().equals(other.sections, sections)&&(identical(other.keepDays, keepDays) || other.keepDays == keepDays));
}


@override
int get hashCode {
    return Object.hash(runtimeType,exportSecrets,const DeepCollectionEquality().hash(sendLinks),const DeepCollectionEquality().hash(sections),keepDays);
}

@override
String toString() {
    return 'BackupsAttrs(exportSecrets: $exportSecrets, sendLinks: $sendLinks, sections: $sections, keepDays: $keepDays)';
}


}

/// @nodoc
abstract mixin class _$BackupsAttrsCopyWith<$Res> implements $BackupsAttrsCopyWith<$Res> {
  factory _$BackupsAttrsCopyWith(_BackupsAttrs value, $Res Function(_BackupsAttrs) _then) = __$BackupsAttrsCopyWithImpl;
@override @useResult
$Res call({
 bool exportSecrets, IList<SendLink> sendLinks, IList<BackupSection> sections, int keepDays
});




}
/// @nodoc
class __$BackupsAttrsCopyWithImpl<$Res>
    implements _$BackupsAttrsCopyWith<$Res> {
  __$BackupsAttrsCopyWithImpl(this._self, this._then);

  final _BackupsAttrs _self;
  final $Res Function(_BackupsAttrs) _then;

/// Create a copy of BackupsAttrs
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? exportSecrets = null,Object? sendLinks = null,Object? sections = null,Object? keepDays = null,}) {
  return _then(_BackupsAttrs(
exportSecrets: null == exportSecrets ? _self.exportSecrets : exportSecrets // ignore: cast_nullable_to_non_nullable
as bool,sendLinks: null == sendLinks ? _self.sendLinks : sendLinks // ignore: cast_nullable_to_non_nullable
as IList<SendLink>,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as IList<BackupSection>,keepDays: null == keepDays ? _self.keepDays : keepDays // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
