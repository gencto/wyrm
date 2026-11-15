// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gateway_types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GatewayInfo {

 String get site; String get version; bool get tls; GatewayRole get role;/// The standby's `host:port`, when the active announces one.
 String? get pair;/// The upstream sites of the broker.
 List<String> get up;/// The oldest Studio the gateway serves.
 String get minStudio;/// The CA code (32 hex digits), over TLS when the broker knows its CA.
/// Sent by an untrusted server: a client computes its own from [ca].
 String? get caFp;/// The CA certificate (DER).
 Uint8List? get ca;/// The DNS and IP names of the gateway's certificate.
 List<String> get names; DevicePolicy get devices;
/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayInfoCopyWith<GatewayInfo> get copyWith => _$GatewayInfoCopyWithImpl<GatewayInfo>(this as GatewayInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GatewayInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayInfo&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.tls, _this.tls) || other.tls == _this.tls)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.pair, _this.pair) || other.pair == _this.pair)&&const DeepCollectionEquality().equals(other.up, _this.up)&&(identical(other.minStudio, _this.minStudio) || other.minStudio == _this.minStudio)&&(identical(other.caFp, _this.caFp) || other.caFp == _this.caFp)&&const DeepCollectionEquality().equals(other.ca, _this.ca)&&const DeepCollectionEquality().equals(other.names, _this.names)&&(identical(other.devices, _this.devices) || other.devices == _this.devices));
}


@override
int get hashCode {
  final _this = this as GatewayInfo;
  return Object.hash(runtimeType,_this.site,_this.version,_this.tls,_this.role,_this.pair,const DeepCollectionEquality().hash(_this.up),_this.minStudio,_this.caFp,const DeepCollectionEquality().hash(_this.ca),const DeepCollectionEquality().hash(_this.names),_this.devices);
}

@override
String toString() {
  final _this = this as GatewayInfo;
  return 'GatewayInfo(site: ${_this.site}, version: ${_this.version}, tls: ${_this.tls}, role: ${_this.role}, pair: ${_this.pair}, up: ${_this.up}, minStudio: ${_this.minStudio}, caFp: ${_this.caFp}, ca: ${_this.ca}, names: ${_this.names}, devices: ${_this.devices})';
}


}

/// @nodoc
abstract mixin class $GatewayInfoCopyWith<$Res>  {
  factory $GatewayInfoCopyWith(GatewayInfo value, $Res Function(GatewayInfo) _then) = _$GatewayInfoCopyWithImpl;
@useResult
$Res call({
 String site, String version, bool tls, GatewayRole role, String? pair, List<String> up, String minStudio, String? caFp, Uint8List? ca, List<String> names, DevicePolicy devices
});


$DevicePolicyCopyWith<$Res> get devices;

}
/// @nodoc
class _$GatewayInfoCopyWithImpl<$Res>
    implements $GatewayInfoCopyWith<$Res> {
  _$GatewayInfoCopyWithImpl(this._self, this._then);

  final GatewayInfo _self;
  final $Res Function(GatewayInfo) _then;

/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? site = null,Object? version = null,Object? tls = null,Object? role = null,Object? pair = freezed,Object? up = null,Object? minStudio = null,Object? caFp = freezed,Object? ca = freezed,Object? names = null,Object? devices = null,}) {
  return _then(GatewayInfo(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,tls: null == tls ? _self.tls : tls // ignore: cast_nullable_to_non_nullable
as bool,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as GatewayRole,pair: freezed == pair ? _self.pair : pair // ignore: cast_nullable_to_non_nullable
as String?,up: null == up ? _self.up : up // ignore: cast_nullable_to_non_nullable
as List<String>,minStudio: null == minStudio ? _self.minStudio : minStudio // ignore: cast_nullable_to_non_nullable
as String,caFp: freezed == caFp ? _self.caFp : caFp // ignore: cast_nullable_to_non_nullable
as String?,ca: freezed == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as Uint8List?,names: null == names ? _self.names : names // ignore: cast_nullable_to_non_nullable
as List<String>,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as DevicePolicy,
  ));
}
/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DevicePolicyCopyWith<$Res> get devices {
  
  return $DevicePolicyCopyWith<$Res>(_self.devices, (value) {
    return _then(_self.copyWith(devices: value));
  });
}
}


/// Adds pattern-matching-related methods to [GatewayInfo].
extension GatewayInfoPatterns on GatewayInfo {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GatewayInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GatewayInfo() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GatewayInfo value)  $default,){
final _that = this;
switch (_that) {
case _GatewayInfo():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GatewayInfo value)?  $default,){
final _that = this;
switch (_that) {
case _GatewayInfo() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String site,  String version,  bool tls,  GatewayRole role,  String? pair,  List<String> up,  String minStudio,  String? caFp,  Uint8List? ca,  List<String> names,  DevicePolicy devices)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GatewayInfo() when $default != null:
return $default(_that.site,_that.version,_that.tls,_that.role,_that.pair,_that.up,_that.minStudio,_that.caFp,_that.ca,_that.names,_that.devices);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String site,  String version,  bool tls,  GatewayRole role,  String? pair,  List<String> up,  String minStudio,  String? caFp,  Uint8List? ca,  List<String> names,  DevicePolicy devices)  $default,) {final _that = this;
switch (_that) {
case _GatewayInfo():
return $default(_that.site,_that.version,_that.tls,_that.role,_that.pair,_that.up,_that.minStudio,_that.caFp,_that.ca,_that.names,_that.devices);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String site,  String version,  bool tls,  GatewayRole role,  String? pair,  List<String> up,  String minStudio,  String? caFp,  Uint8List? ca,  List<String> names,  DevicePolicy devices)?  $default,) {final _that = this;
switch (_that) {
case _GatewayInfo() when $default != null:
return $default(_that.site,_that.version,_that.tls,_that.role,_that.pair,_that.up,_that.minStudio,_that.caFp,_that.ca,_that.names,_that.devices);case _:
  return null;

}
}

}

/// @nodoc


class _GatewayInfo extends GatewayInfo {
  const _GatewayInfo({required this.site, required this.version, required this.tls, this.role = GatewayRole.active, this.pair,  List<String> up = const <String>[], this.minStudio = '0', this.caFp, this.ca,  List<String> names = const <String>[], this.devices = const DevicePolicy()}): _up = up,_names = names,super._();
  

@override final  String site;
@override final  String version;
@override final  bool tls;
@override@JsonKey() final  GatewayRole role;
/// The standby's `host:port`, when the active announces one.
@override final  String? pair;
/// The upstream sites of the broker.
 final  List<String> _up;
/// The upstream sites of the broker.
@override@JsonKey() List<String> get up {
  if (_up is EqualUnmodifiableListView) return _up;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_up);
}

/// The oldest Studio the gateway serves.
@override@JsonKey() final  String minStudio;
/// The CA code (32 hex digits), over TLS when the broker knows its CA.
/// Sent by an untrusted server: a client computes its own from [ca].
@override final  String? caFp;
/// The CA certificate (DER).
@override final  Uint8List? ca;
/// The DNS and IP names of the gateway's certificate.
 final  List<String> _names;
/// The DNS and IP names of the gateway's certificate.
@override@JsonKey() List<String> get names {
  if (_names is EqualUnmodifiableListView) return _names;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_names);
}

@override@JsonKey() final  DevicePolicy devices;

/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GatewayInfoCopyWith<_GatewayInfo> get copyWith => __$GatewayInfoCopyWithImpl<_GatewayInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GatewayInfo&&(identical(other.site, site) || other.site == site)&&(identical(other.version, version) || other.version == version)&&(identical(other.tls, tls) || other.tls == tls)&&(identical(other.role, role) || other.role == role)&&(identical(other.pair, pair) || other.pair == pair)&&const DeepCollectionEquality().equals(other.up, _up)&&(identical(other.minStudio, minStudio) || other.minStudio == minStudio)&&(identical(other.caFp, caFp) || other.caFp == caFp)&&const DeepCollectionEquality().equals(other.ca, ca)&&const DeepCollectionEquality().equals(other.names, _names)&&(identical(other.devices, devices) || other.devices == devices));
}


@override
int get hashCode {
    return Object.hash(runtimeType,site,version,tls,role,pair,const DeepCollectionEquality().hash(_up),minStudio,caFp,const DeepCollectionEquality().hash(ca),const DeepCollectionEquality().hash(_names),devices);
}

@override
String toString() {
    return 'GatewayInfo(site: $site, version: $version, tls: $tls, role: $role, pair: $pair, up: $up, minStudio: $minStudio, caFp: $caFp, ca: $ca, names: $names, devices: $devices)';
}


}

/// @nodoc
abstract mixin class _$GatewayInfoCopyWith<$Res> implements $GatewayInfoCopyWith<$Res> {
  factory _$GatewayInfoCopyWith(_GatewayInfo value, $Res Function(_GatewayInfo) _then) = __$GatewayInfoCopyWithImpl;
@override @useResult
$Res call({
 String site, String version, bool tls, GatewayRole role, String? pair, List<String> up, String minStudio, String? caFp, Uint8List? ca, List<String> names, DevicePolicy devices
});


@override $DevicePolicyCopyWith<$Res> get devices;

}
/// @nodoc
class __$GatewayInfoCopyWithImpl<$Res>
    implements _$GatewayInfoCopyWith<$Res> {
  __$GatewayInfoCopyWithImpl(this._self, this._then);

  final _GatewayInfo _self;
  final $Res Function(_GatewayInfo) _then;

/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? site = null,Object? version = null,Object? tls = null,Object? role = null,Object? pair = freezed,Object? up = null,Object? minStudio = null,Object? caFp = freezed,Object? ca = freezed,Object? names = null,Object? devices = null,}) {
  return _then(_GatewayInfo(
site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,tls: null == tls ? _self.tls : tls // ignore: cast_nullable_to_non_nullable
as bool,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as GatewayRole,pair: freezed == pair ? _self.pair : pair // ignore: cast_nullable_to_non_nullable
as String?,up: null == up ? _self._up : up // ignore: cast_nullable_to_non_nullable
as List<String>,minStudio: null == minStudio ? _self.minStudio : minStudio // ignore: cast_nullable_to_non_nullable
as String,caFp: freezed == caFp ? _self.caFp : caFp // ignore: cast_nullable_to_non_nullable
as String?,ca: freezed == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as Uint8List?,names: null == names ? _self._names : names // ignore: cast_nullable_to_non_nullable
as List<String>,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as DevicePolicy,
  ));
}

/// Create a copy of GatewayInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DevicePolicyCopyWith<$Res> get devices {
  
  return $DevicePolicyCopyWith<$Res>(_self.devices, (value) {
    return _then(_self.copyWith(devices: value));
  });
}
}

/// @nodoc
mixin _$DevicePolicy {

 bool get enabled; int get maxPerUser; int get passwordEveryDays; int get idleLockMaxMin; StepUp get stepUp; bool get allowDeviceCredential;
/// Create a copy of DevicePolicy
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DevicePolicyCopyWith<DevicePolicy> get copyWith => _$DevicePolicyCopyWithImpl<DevicePolicy>(this as DevicePolicy, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DevicePolicy;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DevicePolicy&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.maxPerUser, _this.maxPerUser) || other.maxPerUser == _this.maxPerUser)&&(identical(other.passwordEveryDays, _this.passwordEveryDays) || other.passwordEveryDays == _this.passwordEveryDays)&&(identical(other.idleLockMaxMin, _this.idleLockMaxMin) || other.idleLockMaxMin == _this.idleLockMaxMin)&&(identical(other.stepUp, _this.stepUp) || other.stepUp == _this.stepUp)&&(identical(other.allowDeviceCredential, _this.allowDeviceCredential) || other.allowDeviceCredential == _this.allowDeviceCredential));
}


@override
int get hashCode {
  final _this = this as DevicePolicy;
  return Object.hash(runtimeType,_this.enabled,_this.maxPerUser,_this.passwordEveryDays,_this.idleLockMaxMin,_this.stepUp,_this.allowDeviceCredential);
}

@override
String toString() {
  final _this = this as DevicePolicy;
  return 'DevicePolicy(enabled: ${_this.enabled}, maxPerUser: ${_this.maxPerUser}, passwordEveryDays: ${_this.passwordEveryDays}, idleLockMaxMin: ${_this.idleLockMaxMin}, stepUp: ${_this.stepUp}, allowDeviceCredential: ${_this.allowDeviceCredential})';
}


}

/// @nodoc
abstract mixin class $DevicePolicyCopyWith<$Res>  {
  factory $DevicePolicyCopyWith(DevicePolicy value, $Res Function(DevicePolicy) _then) = _$DevicePolicyCopyWithImpl;
@useResult
$Res call({
 bool enabled, int maxPerUser, int passwordEveryDays, int idleLockMaxMin, StepUp stepUp, bool allowDeviceCredential
});




}
/// @nodoc
class _$DevicePolicyCopyWithImpl<$Res>
    implements $DevicePolicyCopyWith<$Res> {
  _$DevicePolicyCopyWithImpl(this._self, this._then);

  final DevicePolicy _self;
  final $Res Function(DevicePolicy) _then;

/// Create a copy of DevicePolicy
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? maxPerUser = null,Object? passwordEveryDays = null,Object? idleLockMaxMin = null,Object? stepUp = null,Object? allowDeviceCredential = null,}) {
  return _then(DevicePolicy(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxPerUser: null == maxPerUser ? _self.maxPerUser : maxPerUser // ignore: cast_nullable_to_non_nullable
as int,passwordEveryDays: null == passwordEveryDays ? _self.passwordEveryDays : passwordEveryDays // ignore: cast_nullable_to_non_nullable
as int,idleLockMaxMin: null == idleLockMaxMin ? _self.idleLockMaxMin : idleLockMaxMin // ignore: cast_nullable_to_non_nullable
as int,stepUp: null == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as StepUp,allowDeviceCredential: null == allowDeviceCredential ? _self.allowDeviceCredential : allowDeviceCredential // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [DevicePolicy].
extension DevicePolicyPatterns on DevicePolicy {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DevicePolicy value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DevicePolicy() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DevicePolicy value)  $default,){
final _that = this;
switch (_that) {
case _DevicePolicy():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DevicePolicy value)?  $default,){
final _that = this;
switch (_that) {
case _DevicePolicy() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled,  int maxPerUser,  int passwordEveryDays,  int idleLockMaxMin,  StepUp stepUp,  bool allowDeviceCredential)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DevicePolicy() when $default != null:
return $default(_that.enabled,_that.maxPerUser,_that.passwordEveryDays,_that.idleLockMaxMin,_that.stepUp,_that.allowDeviceCredential);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled,  int maxPerUser,  int passwordEveryDays,  int idleLockMaxMin,  StepUp stepUp,  bool allowDeviceCredential)  $default,) {final _that = this;
switch (_that) {
case _DevicePolicy():
return $default(_that.enabled,_that.maxPerUser,_that.passwordEveryDays,_that.idleLockMaxMin,_that.stepUp,_that.allowDeviceCredential);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled,  int maxPerUser,  int passwordEveryDays,  int idleLockMaxMin,  StepUp stepUp,  bool allowDeviceCredential)?  $default,) {final _that = this;
switch (_that) {
case _DevicePolicy() when $default != null:
return $default(_that.enabled,_that.maxPerUser,_that.passwordEveryDays,_that.idleLockMaxMin,_that.stepUp,_that.allowDeviceCredential);case _:
  return null;

}
}

}

/// @nodoc


class _DevicePolicy extends DevicePolicy {
  const _DevicePolicy({this.enabled = false, this.maxPerUser = 5, this.passwordEveryDays = 30, this.idleLockMaxMin = 30, this.stepUp = StepUp.none, this.allowDeviceCredential = false}): super._();
  

@override@JsonKey() final  bool enabled;
@override@JsonKey() final  int maxPerUser;
@override@JsonKey() final  int passwordEveryDays;
@override@JsonKey() final  int idleLockMaxMin;
@override@JsonKey() final  StepUp stepUp;
@override@JsonKey() final  bool allowDeviceCredential;

/// Create a copy of DevicePolicy
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DevicePolicyCopyWith<_DevicePolicy> get copyWith => __$DevicePolicyCopyWithImpl<_DevicePolicy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DevicePolicy&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.maxPerUser, maxPerUser) || other.maxPerUser == maxPerUser)&&(identical(other.passwordEveryDays, passwordEveryDays) || other.passwordEveryDays == passwordEveryDays)&&(identical(other.idleLockMaxMin, idleLockMaxMin) || other.idleLockMaxMin == idleLockMaxMin)&&(identical(other.stepUp, stepUp) || other.stepUp == stepUp)&&(identical(other.allowDeviceCredential, allowDeviceCredential) || other.allowDeviceCredential == allowDeviceCredential));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled,maxPerUser,passwordEveryDays,idleLockMaxMin,stepUp,allowDeviceCredential);
}

@override
String toString() {
    return 'DevicePolicy(enabled: $enabled, maxPerUser: $maxPerUser, passwordEveryDays: $passwordEveryDays, idleLockMaxMin: $idleLockMaxMin, stepUp: $stepUp, allowDeviceCredential: $allowDeviceCredential)';
}


}

/// @nodoc
abstract mixin class _$DevicePolicyCopyWith<$Res> implements $DevicePolicyCopyWith<$Res> {
  factory _$DevicePolicyCopyWith(_DevicePolicy value, $Res Function(_DevicePolicy) _then) = __$DevicePolicyCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, int maxPerUser, int passwordEveryDays, int idleLockMaxMin, StepUp stepUp, bool allowDeviceCredential
});




}
/// @nodoc
class __$DevicePolicyCopyWithImpl<$Res>
    implements _$DevicePolicyCopyWith<$Res> {
  __$DevicePolicyCopyWithImpl(this._self, this._then);

  final _DevicePolicy _self;
  final $Res Function(_DevicePolicy) _then;

/// Create a copy of DevicePolicy
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? maxPerUser = null,Object? passwordEveryDays = null,Object? idleLockMaxMin = null,Object? stepUp = null,Object? allowDeviceCredential = null,}) {
  return _then(_DevicePolicy(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,maxPerUser: null == maxPerUser ? _self.maxPerUser : maxPerUser // ignore: cast_nullable_to_non_nullable
as int,passwordEveryDays: null == passwordEveryDays ? _self.passwordEveryDays : passwordEveryDays // ignore: cast_nullable_to_non_nullable
as int,idleLockMaxMin: null == idleLockMaxMin ? _self.idleLockMaxMin : idleLockMaxMin // ignore: cast_nullable_to_non_nullable
as int,stepUp: null == stepUp ? _self.stepUp : stepUp // ignore: cast_nullable_to_non_nullable
as StepUp,allowDeviceCredential: null == allowDeviceCredential ? _self.allowDeviceCredential : allowDeviceCredential // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$GatewayDevice {

 String get id; String get name;/// Null: a platform this client does not know ([DevicePlatform]).
 DevicePlatform? get platform; DeviceAlg get alg;/// Seconds since the Unix epoch.
 int get added; int get lastUsed; int get passwordAt; int get passwordDueAt; GatewayDeviceState get state;/// The device of this session.
 bool get thisSession; String? get removedBy; int? get removedAt;
/// Create a copy of GatewayDevice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayDeviceCopyWith<GatewayDevice> get copyWith => _$GatewayDeviceCopyWithImpl<GatewayDevice>(this as GatewayDevice, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GatewayDevice;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayDevice&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.platform, _this.platform) || other.platform == _this.platform)&&(identical(other.alg, _this.alg) || other.alg == _this.alg)&&(identical(other.added, _this.added) || other.added == _this.added)&&(identical(other.lastUsed, _this.lastUsed) || other.lastUsed == _this.lastUsed)&&(identical(other.passwordAt, _this.passwordAt) || other.passwordAt == _this.passwordAt)&&(identical(other.passwordDueAt, _this.passwordDueAt) || other.passwordDueAt == _this.passwordDueAt)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.thisSession, _this.thisSession) || other.thisSession == _this.thisSession)&&(identical(other.removedBy, _this.removedBy) || other.removedBy == _this.removedBy)&&(identical(other.removedAt, _this.removedAt) || other.removedAt == _this.removedAt));
}


@override
int get hashCode {
  final _this = this as GatewayDevice;
  return Object.hash(runtimeType,_this.id,_this.name,_this.platform,_this.alg,_this.added,_this.lastUsed,_this.passwordAt,_this.passwordDueAt,_this.state,_this.thisSession,_this.removedBy,_this.removedAt);
}

@override
String toString() {
  final _this = this as GatewayDevice;
  return 'GatewayDevice(id: ${_this.id}, name: ${_this.name}, platform: ${_this.platform}, alg: ${_this.alg}, added: ${_this.added}, lastUsed: ${_this.lastUsed}, passwordAt: ${_this.passwordAt}, passwordDueAt: ${_this.passwordDueAt}, state: ${_this.state}, thisSession: ${_this.thisSession}, removedBy: ${_this.removedBy}, removedAt: ${_this.removedAt})';
}


}

/// @nodoc
abstract mixin class $GatewayDeviceCopyWith<$Res>  {
  factory $GatewayDeviceCopyWith(GatewayDevice value, $Res Function(GatewayDevice) _then) = _$GatewayDeviceCopyWithImpl;
@useResult
$Res call({
 String id, String name, DevicePlatform? platform, DeviceAlg alg, int added, int lastUsed, int passwordAt, int passwordDueAt, GatewayDeviceState state, bool thisSession, String? removedBy, int? removedAt
});




}
/// @nodoc
class _$GatewayDeviceCopyWithImpl<$Res>
    implements $GatewayDeviceCopyWith<$Res> {
  _$GatewayDeviceCopyWithImpl(this._self, this._then);

  final GatewayDevice _self;
  final $Res Function(GatewayDevice) _then;

/// Create a copy of GatewayDevice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? platform = freezed,Object? alg = null,Object? added = null,Object? lastUsed = null,Object? passwordAt = null,Object? passwordDueAt = null,Object? state = null,Object? thisSession = null,Object? removedBy = freezed,Object? removedAt = freezed,}) {
  return _then(GatewayDevice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as DevicePlatform?,alg: null == alg ? _self.alg : alg // ignore: cast_nullable_to_non_nullable
as DeviceAlg,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,passwordAt: null == passwordAt ? _self.passwordAt : passwordAt // ignore: cast_nullable_to_non_nullable
as int,passwordDueAt: null == passwordDueAt ? _self.passwordDueAt : passwordDueAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as GatewayDeviceState,thisSession: null == thisSession ? _self.thisSession : thisSession // ignore: cast_nullable_to_non_nullable
as bool,removedBy: freezed == removedBy ? _self.removedBy : removedBy // ignore: cast_nullable_to_non_nullable
as String?,removedAt: freezed == removedAt ? _self.removedAt : removedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [GatewayDevice].
extension GatewayDevicePatterns on GatewayDevice {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GatewayDevice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GatewayDevice() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GatewayDevice value)  $default,){
final _that = this;
switch (_that) {
case _GatewayDevice():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GatewayDevice value)?  $default,){
final _that = this;
switch (_that) {
case _GatewayDevice() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  DevicePlatform? platform,  DeviceAlg alg,  int added,  int lastUsed,  int passwordAt,  int passwordDueAt,  GatewayDeviceState state,  bool thisSession,  String? removedBy,  int? removedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GatewayDevice() when $default != null:
return $default(_that.id,_that.name,_that.platform,_that.alg,_that.added,_that.lastUsed,_that.passwordAt,_that.passwordDueAt,_that.state,_that.thisSession,_that.removedBy,_that.removedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  DevicePlatform? platform,  DeviceAlg alg,  int added,  int lastUsed,  int passwordAt,  int passwordDueAt,  GatewayDeviceState state,  bool thisSession,  String? removedBy,  int? removedAt)  $default,) {final _that = this;
switch (_that) {
case _GatewayDevice():
return $default(_that.id,_that.name,_that.platform,_that.alg,_that.added,_that.lastUsed,_that.passwordAt,_that.passwordDueAt,_that.state,_that.thisSession,_that.removedBy,_that.removedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  DevicePlatform? platform,  DeviceAlg alg,  int added,  int lastUsed,  int passwordAt,  int passwordDueAt,  GatewayDeviceState state,  bool thisSession,  String? removedBy,  int? removedAt)?  $default,) {final _that = this;
switch (_that) {
case _GatewayDevice() when $default != null:
return $default(_that.id,_that.name,_that.platform,_that.alg,_that.added,_that.lastUsed,_that.passwordAt,_that.passwordDueAt,_that.state,_that.thisSession,_that.removedBy,_that.removedAt);case _:
  return null;

}
}

}

/// @nodoc


class _GatewayDevice extends GatewayDevice {
  const _GatewayDevice({required this.id, required this.name, required this.platform, this.alg = DeviceAlg.es256, this.added = 0, this.lastUsed = 0, this.passwordAt = 0, this.passwordDueAt = 0, this.state = GatewayDeviceState.active, this.thisSession = false, this.removedBy, this.removedAt}): super._();
  

@override final  String id;
@override final  String name;
/// Null: a platform this client does not know ([DevicePlatform]).
@override final  DevicePlatform? platform;
@override@JsonKey() final  DeviceAlg alg;
/// Seconds since the Unix epoch.
@override@JsonKey() final  int added;
@override@JsonKey() final  int lastUsed;
@override@JsonKey() final  int passwordAt;
@override@JsonKey() final  int passwordDueAt;
@override@JsonKey() final  GatewayDeviceState state;
/// The device of this session.
@override@JsonKey() final  bool thisSession;
@override final  String? removedBy;
@override final  int? removedAt;

/// Create a copy of GatewayDevice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GatewayDeviceCopyWith<_GatewayDevice> get copyWith => __$GatewayDeviceCopyWithImpl<_GatewayDevice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GatewayDevice&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.platform, platform) || other.platform == platform)&&(identical(other.alg, alg) || other.alg == alg)&&(identical(other.added, added) || other.added == added)&&(identical(other.lastUsed, lastUsed) || other.lastUsed == lastUsed)&&(identical(other.passwordAt, passwordAt) || other.passwordAt == passwordAt)&&(identical(other.passwordDueAt, passwordDueAt) || other.passwordDueAt == passwordDueAt)&&(identical(other.state, state) || other.state == state)&&(identical(other.thisSession, thisSession) || other.thisSession == thisSession)&&(identical(other.removedBy, removedBy) || other.removedBy == removedBy)&&(identical(other.removedAt, removedAt) || other.removedAt == removedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,platform,alg,added,lastUsed,passwordAt,passwordDueAt,state,thisSession,removedBy,removedAt);
}

@override
String toString() {
    return 'GatewayDevice(id: $id, name: $name, platform: $platform, alg: $alg, added: $added, lastUsed: $lastUsed, passwordAt: $passwordAt, passwordDueAt: $passwordDueAt, state: $state, thisSession: $thisSession, removedBy: $removedBy, removedAt: $removedAt)';
}


}

/// @nodoc
abstract mixin class _$GatewayDeviceCopyWith<$Res> implements $GatewayDeviceCopyWith<$Res> {
  factory _$GatewayDeviceCopyWith(_GatewayDevice value, $Res Function(_GatewayDevice) _then) = __$GatewayDeviceCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, DevicePlatform? platform, DeviceAlg alg, int added, int lastUsed, int passwordAt, int passwordDueAt, GatewayDeviceState state, bool thisSession, String? removedBy, int? removedAt
});




}
/// @nodoc
class __$GatewayDeviceCopyWithImpl<$Res>
    implements _$GatewayDeviceCopyWith<$Res> {
  __$GatewayDeviceCopyWithImpl(this._self, this._then);

  final _GatewayDevice _self;
  final $Res Function(_GatewayDevice) _then;

/// Create a copy of GatewayDevice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? platform = freezed,Object? alg = null,Object? added = null,Object? lastUsed = null,Object? passwordAt = null,Object? passwordDueAt = null,Object? state = null,Object? thisSession = null,Object? removedBy = freezed,Object? removedAt = freezed,}) {
  return _then(_GatewayDevice(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,platform: freezed == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as DevicePlatform?,alg: null == alg ? _self.alg : alg // ignore: cast_nullable_to_non_nullable
as DeviceAlg,added: null == added ? _self.added : added // ignore: cast_nullable_to_non_nullable
as int,lastUsed: null == lastUsed ? _self.lastUsed : lastUsed // ignore: cast_nullable_to_non_nullable
as int,passwordAt: null == passwordAt ? _self.passwordAt : passwordAt // ignore: cast_nullable_to_non_nullable
as int,passwordDueAt: null == passwordDueAt ? _self.passwordDueAt : passwordDueAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as GatewayDeviceState,thisSession: null == thisSession ? _self.thisSession : thisSession // ignore: cast_nullable_to_non_nullable
as bool,removedBy: freezed == removedBy ? _self.removedBy : removedBy // ignore: cast_nullable_to_non_nullable
as String?,removedAt: freezed == removedAt ? _self.removedAt : removedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$GatewayUser {

 String get name; List<String> get roles; bool get disabled;/// Devices that can log in (ADR 0050).
 int get devices;
/// Create a copy of GatewayUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayUserCopyWith<GatewayUser> get copyWith => _$GatewayUserCopyWithImpl<GatewayUser>(this as GatewayUser, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GatewayUser;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayUser&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.roles, _this.roles)&&(identical(other.disabled, _this.disabled) || other.disabled == _this.disabled)&&(identical(other.devices, _this.devices) || other.devices == _this.devices));
}


@override
int get hashCode {
  final _this = this as GatewayUser;
  return Object.hash(runtimeType,_this.name,const DeepCollectionEquality().hash(_this.roles),_this.disabled,_this.devices);
}

@override
String toString() {
  final _this = this as GatewayUser;
  return 'GatewayUser(name: ${_this.name}, roles: ${_this.roles}, disabled: ${_this.disabled}, devices: ${_this.devices})';
}


}

/// @nodoc
abstract mixin class $GatewayUserCopyWith<$Res>  {
  factory $GatewayUserCopyWith(GatewayUser value, $Res Function(GatewayUser) _then) = _$GatewayUserCopyWithImpl;
@useResult
$Res call({
 String name, List<String> roles, bool disabled, int devices
});




}
/// @nodoc
class _$GatewayUserCopyWithImpl<$Res>
    implements $GatewayUserCopyWith<$Res> {
  _$GatewayUserCopyWithImpl(this._self, this._then);

  final GatewayUser _self;
  final $Res Function(GatewayUser) _then;

/// Create a copy of GatewayUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? roles = null,Object? disabled = null,Object? devices = null,}) {
  return _then(GatewayUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<String>,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as bool,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GatewayUser].
extension GatewayUserPatterns on GatewayUser {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GatewayUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GatewayUser() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GatewayUser value)  $default,){
final _that = this;
switch (_that) {
case _GatewayUser():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GatewayUser value)?  $default,){
final _that = this;
switch (_that) {
case _GatewayUser() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  List<String> roles,  bool disabled,  int devices)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GatewayUser() when $default != null:
return $default(_that.name,_that.roles,_that.disabled,_that.devices);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  List<String> roles,  bool disabled,  int devices)  $default,) {final _that = this;
switch (_that) {
case _GatewayUser():
return $default(_that.name,_that.roles,_that.disabled,_that.devices);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  List<String> roles,  bool disabled,  int devices)?  $default,) {final _that = this;
switch (_that) {
case _GatewayUser() when $default != null:
return $default(_that.name,_that.roles,_that.disabled,_that.devices);case _:
  return null;

}
}

}

/// @nodoc


class _GatewayUser extends GatewayUser {
  const _GatewayUser(this.name,  List<String> roles, {this.disabled = false, this.devices = 0}): _roles = roles,super._();
  

@override final  String name;
 final  List<String> _roles;
@override List<String> get roles {
  if (_roles is EqualUnmodifiableListView) return _roles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roles);
}

@override@JsonKey() final  bool disabled;
/// Devices that can log in (ADR 0050).
@override@JsonKey() final  int devices;

/// Create a copy of GatewayUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GatewayUserCopyWith<_GatewayUser> get copyWith => __$GatewayUserCopyWithImpl<_GatewayUser>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GatewayUser&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.roles, _roles)&&(identical(other.disabled, disabled) || other.disabled == disabled)&&(identical(other.devices, devices) || other.devices == devices));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_roles),disabled,devices);
}

@override
String toString() {
    return 'GatewayUser(name: $name, roles: $roles, disabled: $disabled, devices: $devices)';
}


}

/// @nodoc
abstract mixin class _$GatewayUserCopyWith<$Res> implements $GatewayUserCopyWith<$Res> {
  factory _$GatewayUserCopyWith(_GatewayUser value, $Res Function(_GatewayUser) _then) = __$GatewayUserCopyWithImpl;
@override @useResult
$Res call({
 String name, List<String> roles, bool disabled, int devices
});




}
/// @nodoc
class __$GatewayUserCopyWithImpl<$Res>
    implements _$GatewayUserCopyWith<$Res> {
  __$GatewayUserCopyWithImpl(this._self, this._then);

  final _GatewayUser _self;
  final $Res Function(_GatewayUser) _then;

/// Create a copy of GatewayUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? roles = null,Object? disabled = null,Object? devices = null,}) {
  return _then(_GatewayUser(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,null == roles ? _self._roles : roles // ignore: cast_nullable_to_non_nullable
as List<String>,disabled: null == disabled ? _self.disabled : disabled // ignore: cast_nullable_to_non_nullable
as bool,devices: null == devices ? _self.devices : devices // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$GatewayIdentity {

/// `user:<name>` (or `user:<name>@<site>` below an upstream).
 String get sub; List<String> get roles; List<Grant> get grants;/// The highest level any grant gives.
 Perm get max;/// Session expiry, seconds since the Unix epoch.
 int get exp;/// The site this gateway serves.
 String get site;
/// Create a copy of GatewayIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewayIdentityCopyWith<GatewayIdentity> get copyWith => _$GatewayIdentityCopyWithImpl<GatewayIdentity>(this as GatewayIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GatewayIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewayIdentity&&(identical(other.sub, _this.sub) || other.sub == _this.sub)&&const DeepCollectionEquality().equals(other.roles, _this.roles)&&const DeepCollectionEquality().equals(other.grants, _this.grants)&&(identical(other.max, _this.max) || other.max == _this.max)&&(identical(other.exp, _this.exp) || other.exp == _this.exp)&&(identical(other.site, _this.site) || other.site == _this.site));
}


@override
int get hashCode {
  final _this = this as GatewayIdentity;
  return Object.hash(runtimeType,_this.sub,const DeepCollectionEquality().hash(_this.roles),const DeepCollectionEquality().hash(_this.grants),_this.max,_this.exp,_this.site);
}

@override
String toString() {
  final _this = this as GatewayIdentity;
  return 'GatewayIdentity(sub: ${_this.sub}, roles: ${_this.roles}, grants: ${_this.grants}, max: ${_this.max}, exp: ${_this.exp}, site: ${_this.site})';
}


}

/// @nodoc
abstract mixin class $GatewayIdentityCopyWith<$Res>  {
  factory $GatewayIdentityCopyWith(GatewayIdentity value, $Res Function(GatewayIdentity) _then) = _$GatewayIdentityCopyWithImpl;
@useResult
$Res call({
 String sub, List<String> roles, List<Grant> grants, Perm max, int exp, String site
});




}
/// @nodoc
class _$GatewayIdentityCopyWithImpl<$Res>
    implements $GatewayIdentityCopyWith<$Res> {
  _$GatewayIdentityCopyWithImpl(this._self, this._then);

  final GatewayIdentity _self;
  final $Res Function(GatewayIdentity) _then;

/// Create a copy of GatewayIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sub = null,Object? roles = null,Object? grants = null,Object? max = null,Object? exp = null,Object? site = null,}) {
  return _then(GatewayIdentity(
sub: null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as String,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<String>,grants: null == grants ? _self.grants : grants // ignore: cast_nullable_to_non_nullable
as List<Grant>,max: null == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as Perm,exp: null == exp ? _self.exp : exp // ignore: cast_nullable_to_non_nullable
as int,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [GatewayIdentity].
extension GatewayIdentityPatterns on GatewayIdentity {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GatewayIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GatewayIdentity() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GatewayIdentity value)  $default,){
final _that = this;
switch (_that) {
case _GatewayIdentity():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GatewayIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _GatewayIdentity() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sub,  List<String> roles,  List<Grant> grants,  Perm max,  int exp,  String site)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GatewayIdentity() when $default != null:
return $default(_that.sub,_that.roles,_that.grants,_that.max,_that.exp,_that.site);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sub,  List<String> roles,  List<Grant> grants,  Perm max,  int exp,  String site)  $default,) {final _that = this;
switch (_that) {
case _GatewayIdentity():
return $default(_that.sub,_that.roles,_that.grants,_that.max,_that.exp,_that.site);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sub,  List<String> roles,  List<Grant> grants,  Perm max,  int exp,  String site)?  $default,) {final _that = this;
switch (_that) {
case _GatewayIdentity() when $default != null:
return $default(_that.sub,_that.roles,_that.grants,_that.max,_that.exp,_that.site);case _:
  return null;

}
}

}

/// @nodoc


class _GatewayIdentity extends GatewayIdentity {
  const _GatewayIdentity({required this.sub, required  List<String> roles, required  List<Grant> grants, required this.max, required this.exp, required this.site}): _roles = roles,_grants = grants,super._();
  

/// `user:<name>` (or `user:<name>@<site>` below an upstream).
@override final  String sub;
 final  List<String> _roles;
@override List<String> get roles {
  if (_roles is EqualUnmodifiableListView) return _roles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roles);
}

 final  List<Grant> _grants;
@override List<Grant> get grants {
  if (_grants is EqualUnmodifiableListView) return _grants;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_grants);
}

/// The highest level any grant gives.
@override final  Perm max;
/// Session expiry, seconds since the Unix epoch.
@override final  int exp;
/// The site this gateway serves.
@override final  String site;

/// Create a copy of GatewayIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GatewayIdentityCopyWith<_GatewayIdentity> get copyWith => __$GatewayIdentityCopyWithImpl<_GatewayIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GatewayIdentity&&(identical(other.sub, sub) || other.sub == sub)&&const DeepCollectionEquality().equals(other.roles, _roles)&&const DeepCollectionEquality().equals(other.grants, _grants)&&(identical(other.max, max) || other.max == max)&&(identical(other.exp, exp) || other.exp == exp)&&(identical(other.site, site) || other.site == site));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sub,const DeepCollectionEquality().hash(_roles),const DeepCollectionEquality().hash(_grants),max,exp,site);
}

@override
String toString() {
    return 'GatewayIdentity(sub: $sub, roles: $roles, grants: $grants, max: $max, exp: $exp, site: $site)';
}


}

/// @nodoc
abstract mixin class _$GatewayIdentityCopyWith<$Res> implements $GatewayIdentityCopyWith<$Res> {
  factory _$GatewayIdentityCopyWith(_GatewayIdentity value, $Res Function(_GatewayIdentity) _then) = __$GatewayIdentityCopyWithImpl;
@override @useResult
$Res call({
 String sub, List<String> roles, List<Grant> grants, Perm max, int exp, String site
});




}
/// @nodoc
class __$GatewayIdentityCopyWithImpl<$Res>
    implements _$GatewayIdentityCopyWith<$Res> {
  __$GatewayIdentityCopyWithImpl(this._self, this._then);

  final _GatewayIdentity _self;
  final $Res Function(_GatewayIdentity) _then;

/// Create a copy of GatewayIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sub = null,Object? roles = null,Object? grants = null,Object? max = null,Object? exp = null,Object? site = null,}) {
  return _then(_GatewayIdentity(
sub: null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as String,roles: null == roles ? _self._roles : roles // ignore: cast_nullable_to_non_nullable
as List<String>,grants: null == grants ? _self._grants : grants // ignore: cast_nullable_to_non_nullable
as List<Grant>,max: null == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as Perm,exp: null == exp ? _self.exp : exp // ignore: cast_nullable_to_non_nullable
as int,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$GatewaySession {

 String get session;/// Seconds since the Unix epoch; 0 when the gateway did not say.
 int get exp;
/// Create a copy of GatewaySession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GatewaySessionCopyWith<GatewaySession> get copyWith => _$GatewaySessionCopyWithImpl<GatewaySession>(this as GatewaySession, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GatewaySession;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GatewaySession&&(identical(other.session, _this.session) || other.session == _this.session)&&(identical(other.exp, _this.exp) || other.exp == _this.exp));
}


@override
int get hashCode {
  final _this = this as GatewaySession;
  return Object.hash(runtimeType,_this.session,_this.exp);
}



}

/// @nodoc
abstract mixin class $GatewaySessionCopyWith<$Res>  {
  factory $GatewaySessionCopyWith(GatewaySession value, $Res Function(GatewaySession) _then) = _$GatewaySessionCopyWithImpl;
@useResult
$Res call({
 String session, int exp
});




}
/// @nodoc
class _$GatewaySessionCopyWithImpl<$Res>
    implements $GatewaySessionCopyWith<$Res> {
  _$GatewaySessionCopyWithImpl(this._self, this._then);

  final GatewaySession _self;
  final $Res Function(GatewaySession) _then;

/// Create a copy of GatewaySession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? session = null,Object? exp = null,}) {
  return _then(GatewaySession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as String,exp: null == exp ? _self.exp : exp // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GatewaySession].
extension GatewaySessionPatterns on GatewaySession {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GatewaySession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GatewaySession() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GatewaySession value)  $default,){
final _that = this;
switch (_that) {
case _GatewaySession():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GatewaySession value)?  $default,){
final _that = this;
switch (_that) {
case _GatewaySession() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String session,  int exp)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GatewaySession() when $default != null:
return $default(_that.session,_that.exp);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String session,  int exp)  $default,) {final _that = this;
switch (_that) {
case _GatewaySession():
return $default(_that.session,_that.exp);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String session,  int exp)?  $default,) {final _that = this;
switch (_that) {
case _GatewaySession() when $default != null:
return $default(_that.session,_that.exp);case _:
  return null;

}
}

}

/// @nodoc


class _GatewaySession extends GatewaySession {
  const _GatewaySession({required this.session, this.exp = 0}): super._();
  

@override final  String session;
/// Seconds since the Unix epoch; 0 when the gateway did not say.
@override@JsonKey() final  int exp;

/// Create a copy of GatewaySession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GatewaySessionCopyWith<_GatewaySession> get copyWith => __$GatewaySessionCopyWithImpl<_GatewaySession>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GatewaySession&&(identical(other.session, session) || other.session == session)&&(identical(other.exp, exp) || other.exp == exp));
}


@override
int get hashCode {
    return Object.hash(runtimeType,session,exp);
}



}

/// @nodoc
abstract mixin class _$GatewaySessionCopyWith<$Res> implements $GatewaySessionCopyWith<$Res> {
  factory _$GatewaySessionCopyWith(_GatewaySession value, $Res Function(_GatewaySession) _then) = __$GatewaySessionCopyWithImpl;
@override @useResult
$Res call({
 String session, int exp
});




}
/// @nodoc
class __$GatewaySessionCopyWithImpl<$Res>
    implements _$GatewaySessionCopyWith<$Res> {
  __$GatewaySessionCopyWithImpl(this._self, this._then);

  final _GatewaySession _self;
  final $Res Function(_GatewaySession) _then;

/// Create a copy of GatewaySession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? session = null,Object? exp = null,}) {
  return _then(_GatewaySession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as String,exp: null == exp ? _self.exp : exp // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
