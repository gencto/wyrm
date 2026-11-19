// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_link_facts.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupLinkFacts {

 String get id; LinkMode get mode; String get driver; String get site;/// The version of the broker that made the backup.
 String get broker; DateTime get created;
/// Create a copy of BackupLinkFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupLinkFactsCopyWith<BackupLinkFacts> get copyWith => _$BackupLinkFactsCopyWithImpl<BackupLinkFacts>(this as BackupLinkFacts, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BackupLinkFacts;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupLinkFacts&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.driver, _this.driver) || other.driver == _this.driver)&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.broker, _this.broker) || other.broker == _this.broker)&&(identical(other.created, _this.created) || other.created == _this.created));
}


@override
int get hashCode {
  final _this = this as BackupLinkFacts;
  return Object.hash(runtimeType,_this.id,_this.mode,_this.driver,_this.site,_this.broker,_this.created);
}

@override
String toString() {
  final _this = this as BackupLinkFacts;
  return 'BackupLinkFacts(id: ${_this.id}, mode: ${_this.mode}, driver: ${_this.driver}, site: ${_this.site}, broker: ${_this.broker}, created: ${_this.created})';
}


}

/// @nodoc
abstract mixin class $BackupLinkFactsCopyWith<$Res>  {
  factory $BackupLinkFactsCopyWith(BackupLinkFacts value, $Res Function(BackupLinkFacts) _then) = _$BackupLinkFactsCopyWithImpl;
@useResult
$Res call({
 String id, LinkMode mode, String driver, String site, String broker, DateTime created
});




}
/// @nodoc
class _$BackupLinkFactsCopyWithImpl<$Res>
    implements $BackupLinkFactsCopyWith<$Res> {
  _$BackupLinkFactsCopyWithImpl(this._self, this._then);

  final BackupLinkFacts _self;
  final $Res Function(BackupLinkFacts) _then;

/// Create a copy of BackupLinkFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? mode = null,Object? driver = null,Object? site = null,Object? broker = null,Object? created = null,}) {
  return _then(BackupLinkFacts(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,broker: null == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}



/// @nodoc


class _BackupLinkFacts implements BackupLinkFacts {
  const _BackupLinkFacts({required this.id, required this.mode, required this.driver, required this.site, required this.broker, required this.created});
  

@override final  String id;
@override final  LinkMode mode;
@override final  String driver;
@override final  String site;
/// The version of the broker that made the backup.
@override final  String broker;
@override final  DateTime created;

/// Create a copy of BackupLinkFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupLinkFactsCopyWith<_BackupLinkFacts> get copyWith => __$BackupLinkFactsCopyWithImpl<_BackupLinkFacts>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupLinkFacts&&(identical(other.id, id) || other.id == id)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.site, site) || other.site == site)&&(identical(other.broker, broker) || other.broker == broker)&&(identical(other.created, created) || other.created == created));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,mode,driver,site,broker,created);
}

@override
String toString() {
    return 'BackupLinkFacts(id: $id, mode: $mode, driver: $driver, site: $site, broker: $broker, created: $created)';
}


}

/// @nodoc
abstract mixin class _$BackupLinkFactsCopyWith<$Res> implements $BackupLinkFactsCopyWith<$Res> {
  factory _$BackupLinkFactsCopyWith(_BackupLinkFacts value, $Res Function(_BackupLinkFacts) _then) = __$BackupLinkFactsCopyWithImpl;
@override @useResult
$Res call({
 String id, LinkMode mode, String driver, String site, String broker, DateTime created
});




}
/// @nodoc
class __$BackupLinkFactsCopyWithImpl<$Res>
    implements _$BackupLinkFactsCopyWith<$Res> {
  __$BackupLinkFactsCopyWithImpl(this._self, this._then);

  final _BackupLinkFacts _self;
  final $Res Function(_BackupLinkFacts) _then;

/// Create a copy of BackupLinkFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? mode = null,Object? driver = null,Object? site = null,Object? broker = null,Object? created = null,}) {
  return _then(_BackupLinkFacts(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,broker: null == broker ? _self.broker : broker // ignore: cast_nullable_to_non_nullable
as String,created: null == created ? _self.created : created // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
