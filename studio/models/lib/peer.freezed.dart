// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'peer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Peer {

 String get site; PeerKind get kind;/// The site it is relayed through, or the broker it hangs from.
 String? get parent; bool get connected; String? get url; String? get status; bool? get allowConfig; num? get valHz; IList<String> get via;/// Platform upstreams: mqtt, sparkplug, thingsboard, azure, aws.
 String? get platform;
/// Create a copy of Peer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PeerCopyWith<Peer> get copyWith => _$PeerCopyWithImpl<Peer>(this as Peer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Peer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Peer&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&(identical(other.connected, _this.connected) || other.connected == _this.connected)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.allowConfig, _this.allowConfig) || other.allowConfig == _this.allowConfig)&&(identical(other.valHz, _this.valHz) || other.valHz == _this.valHz)&&const DeepCollectionEquality().equals(other.via, _this.via)&&(identical(other.platform, _this.platform) || other.platform == _this.platform));
}


@override
int get hashCode {
  final _this = this as Peer;
  return Object.hash(runtimeType,_this.site,_this.kind,_this.parent,_this.connected,_this.url,_this.status,_this.allowConfig,_this.valHz,const DeepCollectionEquality().hash(_this.via),_this.platform);
}

@override
String toString() {
  final _this = this as Peer;
  return 'Peer(site: ${_this.site}, kind: ${_this.kind}, parent: ${_this.parent}, connected: ${_this.connected}, url: ${_this.url}, status: ${_this.status}, allowConfig: ${_this.allowConfig}, valHz: ${_this.valHz}, via: ${_this.via}, platform: ${_this.platform})';
}


}

/// @nodoc
abstract mixin class $PeerCopyWith<$Res>  {
  factory $PeerCopyWith(Peer value, $Res Function(Peer) _then) = _$PeerCopyWithImpl;
@useResult
$Res call({
 String site, PeerKind kind, String? parent, bool connected, String? url, String? status, bool? allowConfig, num? valHz, IList<String> via, String? platform
});




}
/// @nodoc
class _$PeerCopyWithImpl<$Res>
    implements $PeerCopyWith<$Res> {
  _$PeerCopyWithImpl(this._self, this._then);

  final Peer _self;
  final $Res Function(Peer) _then;

/// Create a copy of Peer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? kind = null,Object? parent = freezed,Object? connected = null,Object? url = freezed,Object? status = freezed,Object? allowConfig = freezed,Object? valHz = freezed,Object? via = null,Object? platform = freezed,}) {
  return _then(Peer(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PeerKind,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,allowConfig: freezed == allowConfig ? _self.allowConfig : allowConfig // ignore: cast_nullable_to_non_nullable
as bool?,valHz: freezed == valHz ? _self.valHz : valHz // ignore: cast_nullable_to_non_nullable
as num?,via: null == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as IList<String>,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _Peer implements Peer {
  const _Peer({required this.site, required this.kind, this.parent, this.connected = false, this.url, this.status, this.allowConfig, this.valHz, this.via = const IListConst([]), this.platform});
  

@override final  String site;
@override final  PeerKind kind;
/// The site it is relayed through, or the broker it hangs from.
@override final  String? parent;
@override@JsonKey() final  bool connected;
@override final  String? url;
@override final  String? status;
@override final  bool? allowConfig;
@override final  num? valHz;
@override@JsonKey() final  IList<String> via;
/// Platform upstreams: mqtt, sparkplug, thingsboard, azure, aws.
@override final  String? platform;

/// Create a copy of Peer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PeerCopyWith<_Peer> get copyWith => __$PeerCopyWithImpl<_Peer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Peer&&(identical(other.site, site) || other.site == site)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.parent, parent) || other.parent == parent)&&(identical(other.connected, connected) || other.connected == connected)&&(identical(other.url, url) || other.url == url)&&(identical(other.status, status) || other.status == status)&&(identical(other.allowConfig, allowConfig) || other.allowConfig == allowConfig)&&(identical(other.valHz, valHz) || other.valHz == valHz)&&const DeepCollectionEquality().equals(other.via, via)&&(identical(other.platform, platform) || other.platform == platform));
}


@override
int get hashCode {
    return Object.hash(runtimeType,site,kind,parent,connected,url,status,allowConfig,valHz,const DeepCollectionEquality().hash(via),platform);
}

@override
String toString() {
    return 'Peer(site: $site, kind: $kind, parent: $parent, connected: $connected, url: $url, status: $status, allowConfig: $allowConfig, valHz: $valHz, via: $via, platform: $platform)';
}


}

/// @nodoc
abstract mixin class _$PeerCopyWith<$Res> implements $PeerCopyWith<$Res> {
  factory _$PeerCopyWith(_Peer value, $Res Function(_Peer) _then) = __$PeerCopyWithImpl;
@override @useResult
$Res call({
 String site, PeerKind kind, String? parent, bool connected, String? url, String? status, bool? allowConfig, num? valHz, IList<String> via, String? platform
});




}
/// @nodoc
class __$PeerCopyWithImpl<$Res>
    implements _$PeerCopyWith<$Res> {
  __$PeerCopyWithImpl(this._self, this._then);

  final _Peer _self;
  final $Res Function(_Peer) _then;

/// Create a copy of Peer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? kind = null,Object? parent = freezed,Object? connected = null,Object? url = freezed,Object? status = freezed,Object? allowConfig = freezed,Object? valHz = freezed,Object? via = null,Object? platform = freezed,}) {
  return _then(_Peer(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PeerKind,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,connected: null == connected ? _self.connected : connected // ignore: cast_nullable_to_non_nullable
as bool,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,allowConfig: freezed == allowConfig ? _self.allowConfig : allowConfig // ignore: cast_nullable_to_non_nullable
as bool?,valHz: freezed == valHz ? _self.valHz : valHz // ignore: cast_nullable_to_non_nullable
as num?,via: null == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as IList<String>,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
