// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'found_gateway.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FoundGateway {

/// The site (`/api/info` `site`, else the TXT `site`).
 String get site;/// The hosts as they are shown: `host:port` of the one that answered,
/// then the standby's.
 IList<String> get hosts;/// The gateway URL to fill in; null when the row cannot be used.
 String? get url;/// The standby gateway URL (from `pair`, or from a second host that
/// announced the same site).
 String? get standby;/// The address to connect to when the URL's name does not resolve on
/// this computer (ADR 0050 decision 10); null when the name does.
 String? get connectTo;/// The wyrmd version, when it said.
 String? get version;/// The gateway serves TLS.
 bool get tls;/// `active` or `standby` (ADR 0036), as `/api/info` said.
 String get role;/// The upstream sites of this broker (`up`).
 IList<String> get up;/// The CA code: the first 16 bytes of the SHA-256 of [ca], in hex,
/// computed here from the certificate that would be pinned.
 String? get code;/// The CA certificate (DER, base64), as `/api/info` sent it.
 String? get ca;/// The CA is pinned for the URL's origin or trusted by this computer.
 bool get known;/// The site whose pinned CA signed this gateway's certificate, when it
/// is another origin's pin (the person checked that CA before).
 String? get knownAs;/// Why the row cannot be used; null when it can.
 FoundProblem? get problem;/// The detail of [problem]: the Studio version a gateway needs, the
/// reason there was no answer.
 String? get detail;/// Found by a range probe, not announced.
 bool get probed;/// When it was last seen, milliseconds since the epoch.
 int get seen;
/// Create a copy of FoundGateway
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FoundGatewayCopyWith<FoundGateway> get copyWith => _$FoundGatewayCopyWithImpl<FoundGateway>(this as FoundGateway, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FoundGateway;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FoundGateway&&(identical(other.site, _this.site) || other.site == _this.site)&&const DeepCollectionEquality().equals(other.hosts, _this.hosts)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.standby, _this.standby) || other.standby == _this.standby)&&(identical(other.connectTo, _this.connectTo) || other.connectTo == _this.connectTo)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.tls, _this.tls) || other.tls == _this.tls)&&(identical(other.role, _this.role) || other.role == _this.role)&&const DeepCollectionEquality().equals(other.up, _this.up)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.ca, _this.ca) || other.ca == _this.ca)&&(identical(other.known, _this.known) || other.known == _this.known)&&(identical(other.knownAs, _this.knownAs) || other.knownAs == _this.knownAs)&&(identical(other.problem, _this.problem) || other.problem == _this.problem)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.probed, _this.probed) || other.probed == _this.probed)&&(identical(other.seen, _this.seen) || other.seen == _this.seen));
}


@override
int get hashCode {
  final _this = this as FoundGateway;
  return Object.hash(runtimeType,_this.site,const DeepCollectionEquality().hash(_this.hosts),_this.url,_this.standby,_this.connectTo,_this.version,_this.tls,_this.role,const DeepCollectionEquality().hash(_this.up),_this.code,_this.ca,_this.known,_this.knownAs,_this.problem,_this.detail,_this.probed,_this.seen);
}

@override
String toString() {
  final _this = this as FoundGateway;
  return 'FoundGateway(site: ${_this.site}, hosts: ${_this.hosts}, url: ${_this.url}, standby: ${_this.standby}, connectTo: ${_this.connectTo}, version: ${_this.version}, tls: ${_this.tls}, role: ${_this.role}, up: ${_this.up}, code: ${_this.code}, ca: ${_this.ca}, known: ${_this.known}, knownAs: ${_this.knownAs}, problem: ${_this.problem}, detail: ${_this.detail}, probed: ${_this.probed}, seen: ${_this.seen})';
}


}

/// @nodoc
abstract mixin class $FoundGatewayCopyWith<$Res>  {
  factory $FoundGatewayCopyWith(FoundGateway value, $Res Function(FoundGateway) _then) = _$FoundGatewayCopyWithImpl;
@useResult
$Res call({
 String site, IList<String> hosts, String? url, String? standby, String? connectTo, String? version, bool tls, String role, IList<String> up, String? code, String? ca, bool known, String? knownAs, FoundProblem? problem, String? detail, bool probed, int seen
});




}
/// @nodoc
class _$FoundGatewayCopyWithImpl<$Res>
    implements $FoundGatewayCopyWith<$Res> {
  _$FoundGatewayCopyWithImpl(this._self, this._then);

  final FoundGateway _self;
  final $Res Function(FoundGateway) _then;

/// Create a copy of FoundGateway
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? hosts = null,Object? url = freezed,Object? standby = freezed,Object? connectTo = freezed,Object? version = freezed,Object? tls = null,Object? role = null,Object? up = null,Object? code = freezed,Object? ca = freezed,Object? known = null,Object? knownAs = freezed,Object? problem = freezed,Object? detail = freezed,Object? probed = null,Object? seen = null,}) {
  return _then(FoundGateway(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,hosts: null == hosts ? _self.hosts : hosts // ignore: cast_nullable_to_non_nullable
as IList<String>,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,standby: freezed == standby ? _self.standby : standby // ignore: cast_nullable_to_non_nullable
as String?,connectTo: freezed == connectTo ? _self.connectTo : connectTo // ignore: cast_nullable_to_non_nullable
as String?,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,tls: null == tls ? _self.tls : tls // ignore: cast_nullable_to_non_nullable
as bool,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,up: null == up ? _self.up : up // ignore: cast_nullable_to_non_nullable
as IList<String>,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,ca: freezed == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as String?,known: null == known ? _self.known : known // ignore: cast_nullable_to_non_nullable
as bool,knownAs: freezed == knownAs ? _self.knownAs : knownAs // ignore: cast_nullable_to_non_nullable
as String?,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as FoundProblem?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,probed: null == probed ? _self.probed : probed // ignore: cast_nullable_to_non_nullable
as bool,seen: null == seen ? _self.seen : seen // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _FoundGateway implements FoundGateway {
  const _FoundGateway({required this.site, this.hosts = const IListConst([]), this.url, this.standby, this.connectTo, this.version, this.tls = true, this.role = 'active', this.up = const IListConst([]), this.code, this.ca, this.known = false, this.knownAs, this.problem, this.detail, this.probed = false, this.seen = 0});
  

/// The site (`/api/info` `site`, else the TXT `site`).
@override final  String site;
/// The hosts as they are shown: `host:port` of the one that answered,
/// then the standby's.
@override@JsonKey() final  IList<String> hosts;
/// The gateway URL to fill in; null when the row cannot be used.
@override final  String? url;
/// The standby gateway URL (from `pair`, or from a second host that
/// announced the same site).
@override final  String? standby;
/// The address to connect to when the URL's name does not resolve on
/// this computer (ADR 0050 decision 10); null when the name does.
@override final  String? connectTo;
/// The wyrmd version, when it said.
@override final  String? version;
/// The gateway serves TLS.
@override@JsonKey() final  bool tls;
/// `active` or `standby` (ADR 0036), as `/api/info` said.
@override@JsonKey() final  String role;
/// The upstream sites of this broker (`up`).
@override@JsonKey() final  IList<String> up;
/// The CA code: the first 16 bytes of the SHA-256 of [ca], in hex,
/// computed here from the certificate that would be pinned.
@override final  String? code;
/// The CA certificate (DER, base64), as `/api/info` sent it.
@override final  String? ca;
/// The CA is pinned for the URL's origin or trusted by this computer.
@override@JsonKey() final  bool known;
/// The site whose pinned CA signed this gateway's certificate, when it
/// is another origin's pin (the person checked that CA before).
@override final  String? knownAs;
/// Why the row cannot be used; null when it can.
@override final  FoundProblem? problem;
/// The detail of [problem]: the Studio version a gateway needs, the
/// reason there was no answer.
@override final  String? detail;
/// Found by a range probe, not announced.
@override@JsonKey() final  bool probed;
/// When it was last seen, milliseconds since the epoch.
@override@JsonKey() final  int seen;

/// Create a copy of FoundGateway
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FoundGatewayCopyWith<_FoundGateway> get copyWith => __$FoundGatewayCopyWithImpl<_FoundGateway>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FoundGateway&&(identical(other.site, site) || other.site == site)&&const DeepCollectionEquality().equals(other.hosts, hosts)&&(identical(other.url, url) || other.url == url)&&(identical(other.standby, standby) || other.standby == standby)&&(identical(other.connectTo, connectTo) || other.connectTo == connectTo)&&(identical(other.version, version) || other.version == version)&&(identical(other.tls, tls) || other.tls == tls)&&(identical(other.role, role) || other.role == role)&&const DeepCollectionEquality().equals(other.up, up)&&(identical(other.code, code) || other.code == code)&&(identical(other.ca, ca) || other.ca == ca)&&(identical(other.known, known) || other.known == known)&&(identical(other.knownAs, knownAs) || other.knownAs == knownAs)&&(identical(other.problem, problem) || other.problem == problem)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.probed, probed) || other.probed == probed)&&(identical(other.seen, seen) || other.seen == seen));
}


@override
int get hashCode {
    return Object.hash(runtimeType,site,const DeepCollectionEquality().hash(hosts),url,standby,connectTo,version,tls,role,const DeepCollectionEquality().hash(up),code,ca,known,knownAs,problem,detail,probed,seen);
}

@override
String toString() {
    return 'FoundGateway(site: $site, hosts: $hosts, url: $url, standby: $standby, connectTo: $connectTo, version: $version, tls: $tls, role: $role, up: $up, code: $code, ca: $ca, known: $known, knownAs: $knownAs, problem: $problem, detail: $detail, probed: $probed, seen: $seen)';
}


}

/// @nodoc
abstract mixin class _$FoundGatewayCopyWith<$Res> implements $FoundGatewayCopyWith<$Res> {
  factory _$FoundGatewayCopyWith(_FoundGateway value, $Res Function(_FoundGateway) _then) = __$FoundGatewayCopyWithImpl;
@override @useResult
$Res call({
 String site, IList<String> hosts, String? url, String? standby, String? connectTo, String? version, bool tls, String role, IList<String> up, String? code, String? ca, bool known, String? knownAs, FoundProblem? problem, String? detail, bool probed, int seen
});




}
/// @nodoc
class __$FoundGatewayCopyWithImpl<$Res>
    implements _$FoundGatewayCopyWith<$Res> {
  __$FoundGatewayCopyWithImpl(this._self, this._then);

  final _FoundGateway _self;
  final $Res Function(_FoundGateway) _then;

/// Create a copy of FoundGateway
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? hosts = null,Object? url = freezed,Object? standby = freezed,Object? connectTo = freezed,Object? version = freezed,Object? tls = null,Object? role = null,Object? up = null,Object? code = freezed,Object? ca = freezed,Object? known = null,Object? knownAs = freezed,Object? problem = freezed,Object? detail = freezed,Object? probed = null,Object? seen = null,}) {
  return _then(_FoundGateway(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,hosts: null == hosts ? _self.hosts : hosts // ignore: cast_nullable_to_non_nullable
as IList<String>,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,standby: freezed == standby ? _self.standby : standby // ignore: cast_nullable_to_non_nullable
as String?,connectTo: freezed == connectTo ? _self.connectTo : connectTo // ignore: cast_nullable_to_non_nullable
as String?,version: freezed == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String?,tls: null == tls ? _self.tls : tls // ignore: cast_nullable_to_non_nullable
as bool,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,up: null == up ? _self.up : up // ignore: cast_nullable_to_non_nullable
as IList<String>,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,ca: freezed == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as String?,known: null == known ? _self.known : known // ignore: cast_nullable_to_non_nullable
as bool,knownAs: freezed == knownAs ? _self.knownAs : knownAs // ignore: cast_nullable_to_non_nullable
as String?,problem: freezed == problem ? _self.problem : problem // ignore: cast_nullable_to_non_nullable
as FoundProblem?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,probed: null == probed ? _self.probed : probed // ignore: cast_nullable_to_non_nullable
as bool,seen: null == seen ? _self.seen : seen // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
