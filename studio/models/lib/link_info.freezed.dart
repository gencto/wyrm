// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'link_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkInfo {

 String get id; String get driver; LinkMode get mode;/// installed, starting, connected, stopping, stopped, failed.
 String get state; String? get package; String? get version; String? get source; String? get sha256;/// External links: the device address.
 String? get device; String? get certificateCn; String? get note;/// `config` (from `wyrmd.json5`) or `runtime` (installed or admitted
/// while the broker runs).
 String get origin;
/// Create a copy of LinkInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkInfoCopyWith<LinkInfo> get copyWith => _$LinkInfoCopyWithImpl<LinkInfo>(this as LinkInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.state, state) || other.state == state)&&(identical(other.package, package) || other.package == package)&&(identical(other.version, version) || other.version == version)&&(identical(other.source, source) || other.source == source)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.device, device) || other.device == device)&&(identical(other.certificateCn, certificateCn) || other.certificateCn == certificateCn)&&(identical(other.note, note) || other.note == note)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,id,driver,mode,state,package,version,source,sha256,device,certificateCn,note,origin);

@override
String toString() {
  return 'LinkInfo(id: $id, driver: $driver, mode: $mode, state: $state, package: $package, version: $version, source: $source, sha256: $sha256, device: $device, certificateCn: $certificateCn, note: $note, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $LinkInfoCopyWith<$Res>  {
  factory $LinkInfoCopyWith(LinkInfo value, $Res Function(LinkInfo) _then) = _$LinkInfoCopyWithImpl;
@useResult
$Res call({
 String id, String driver, LinkMode mode, String state, String? package, String? version, String? source, String? sha256, String? device, String? certificateCn, String? note, String origin
});




}
/// @nodoc
class _$LinkInfoCopyWithImpl<$Res>
    implements $LinkInfoCopyWith<$Res> {
  _$LinkInfoCopyWithImpl(this._self, this._then);

  final LinkInfo _self;
  final $Res Function(LinkInfo) _then;

/// Create a copy of LinkInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? driver = null,Object? mode = null,Object? state = null,Object? package = freezed,Object? version = freezed,Object? source = freezed,Object? sha256 = freezed,Object? device = freezed,Object? certificateCn = freezed,Object? note = freezed,Object? origin = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,package: freezed == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String?,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as String?,certificateCn: freezed == certificateCn ? _self.certificateCn : certificateCn // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _LinkInfo implements LinkInfo {
  const _LinkInfo({required this.id, this.driver = '', this.mode = LinkMode.embedded, this.state = 'installed', this.package, this.version, this.source, this.sha256, this.device, this.certificateCn, this.note, this.origin = 'config'});
  

@override final  String id;
@override@JsonKey() final  String driver;
@override@JsonKey() final  LinkMode mode;
/// installed, starting, connected, stopping, stopped, failed.
@override@JsonKey() final  String state;
@override final  String? package;
@override final  String? version;
@override final  String? source;
@override final  String? sha256;
/// External links: the device address.
@override final  String? device;
@override final  String? certificateCn;
@override final  String? note;
/// `config` (from `wyrmd.json5`) or `runtime` (installed or admitted
/// while the broker runs).
@override@JsonKey() final  String origin;

/// Create a copy of LinkInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LinkInfoCopyWith<_LinkInfo> get copyWith => __$LinkInfoCopyWithImpl<_LinkInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LinkInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.driver, driver) || other.driver == driver)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.state, state) || other.state == state)&&(identical(other.package, package) || other.package == package)&&(identical(other.version, version) || other.version == version)&&(identical(other.source, source) || other.source == source)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.device, device) || other.device == device)&&(identical(other.certificateCn, certificateCn) || other.certificateCn == certificateCn)&&(identical(other.note, note) || other.note == note)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,id,driver,mode,state,package,version,source,sha256,device,certificateCn,note,origin);

@override
String toString() {
  return 'LinkInfo(id: $id, driver: $driver, mode: $mode, state: $state, package: $package, version: $version, source: $source, sha256: $sha256, device: $device, certificateCn: $certificateCn, note: $note, origin: $origin)';
}


}

/// @nodoc
abstract mixin class _$LinkInfoCopyWith<$Res> implements $LinkInfoCopyWith<$Res> {
  factory _$LinkInfoCopyWith(_LinkInfo value, $Res Function(_LinkInfo) _then) = __$LinkInfoCopyWithImpl;
@override @useResult
$Res call({
 String id, String driver, LinkMode mode, String state, String? package, String? version, String? source, String? sha256, String? device, String? certificateCn, String? note, String origin
});




}
/// @nodoc
class __$LinkInfoCopyWithImpl<$Res>
    implements _$LinkInfoCopyWith<$Res> {
  __$LinkInfoCopyWithImpl(this._self, this._then);

  final _LinkInfo _self;
  final $Res Function(_LinkInfo) _then;

/// Create a copy of LinkInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? driver = null,Object? mode = null,Object? state = null,Object? package = freezed,Object? version = freezed,Object? source = freezed,Object? sha256 = freezed,Object? device = freezed,Object? certificateCn = freezed,Object? note = freezed,Object? origin = null,}) {
  return _then(_LinkInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,driver: null == driver ? _self.driver : driver // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as LinkMode,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,package: freezed == package ? _self.package : package // ignore: cast_nullable_to_non_nullable
as String?,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,device: freezed == device ? _self.device : device // ignore: cast_nullable_to_non_nullable
as String?,certificateCn: freezed == certificateCn ? _self.certificateCn : certificateCn // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
