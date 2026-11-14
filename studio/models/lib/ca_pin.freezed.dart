// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ca_pin.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CaPin {

/// `https://host:port`.
 String get origin;/// The CA certificate, DER in base64.
 String get ca;/// The CA code (32 hex digits) the person compared.
 String get code;/// The site it was trusted for.
 String get site;/// The address to connect to when the origin's name does not resolve
/// on this computer (ADR 0050 decision 10).
 String? get connectTo;
/// Create a copy of CaPin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CaPinCopyWith<CaPin> get copyWith => _$CaPinCopyWithImpl<CaPin>(this as CaPin, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CaPin;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CaPin&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.ca, _this.ca) || other.ca == _this.ca)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.site, _this.site) || other.site == _this.site)&&(identical(other.connectTo, _this.connectTo) || other.connectTo == _this.connectTo));
}


@override
int get hashCode {
  final _this = this as CaPin;
  return Object.hash(runtimeType,_this.origin,_this.ca,_this.code,_this.site,_this.connectTo);
}

@override
String toString() {
  final _this = this as CaPin;
  return 'CaPin(origin: ${_this.origin}, ca: ${_this.ca}, code: ${_this.code}, site: ${_this.site}, connectTo: ${_this.connectTo})';
}


}

/// @nodoc
abstract mixin class $CaPinCopyWith<$Res>  {
  factory $CaPinCopyWith(CaPin value, $Res Function(CaPin) _then) = _$CaPinCopyWithImpl;
@useResult
$Res call({
 String origin, String ca, String code, String site, String? connectTo
});




}
/// @nodoc
class _$CaPinCopyWithImpl<$Res>
    implements $CaPinCopyWith<$Res> {
  _$CaPinCopyWithImpl(this._self, this._then);

  final CaPin _self;
  final $Res Function(CaPin) _then;

/// Create a copy of CaPin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? ca = null,Object? code = null,Object? site = null,Object? connectTo = freezed,}) {
  return _then(CaPin(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,ca: null == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,connectTo: freezed == connectTo ? _self.connectTo : connectTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _CaPin implements CaPin {
  const _CaPin({required this.origin, required this.ca, required this.code, this.site = '', this.connectTo});
  

/// `https://host:port`.
@override final  String origin;
/// The CA certificate, DER in base64.
@override final  String ca;
/// The CA code (32 hex digits) the person compared.
@override final  String code;
/// The site it was trusted for.
@override@JsonKey() final  String site;
/// The address to connect to when the origin's name does not resolve
/// on this computer (ADR 0050 decision 10).
@override final  String? connectTo;

/// Create a copy of CaPin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CaPinCopyWith<_CaPin> get copyWith => __$CaPinCopyWithImpl<_CaPin>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CaPin&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.ca, ca) || other.ca == ca)&&(identical(other.code, code) || other.code == code)&&(identical(other.site, site) || other.site == site)&&(identical(other.connectTo, connectTo) || other.connectTo == connectTo));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,ca,code,site,connectTo);
}

@override
String toString() {
    return 'CaPin(origin: $origin, ca: $ca, code: $code, site: $site, connectTo: $connectTo)';
}


}

/// @nodoc
abstract mixin class _$CaPinCopyWith<$Res> implements $CaPinCopyWith<$Res> {
  factory _$CaPinCopyWith(_CaPin value, $Res Function(_CaPin) _then) = __$CaPinCopyWithImpl;
@override @useResult
$Res call({
 String origin, String ca, String code, String site, String? connectTo
});




}
/// @nodoc
class __$CaPinCopyWithImpl<$Res>
    implements _$CaPinCopyWith<$Res> {
  __$CaPinCopyWithImpl(this._self, this._then);

  final _CaPin _self;
  final $Res Function(_CaPin) _then;

/// Create a copy of CaPin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? ca = null,Object? code = null,Object? site = null,Object? connectTo = freezed,}) {
  return _then(_CaPin(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,ca: null == ca ? _self.ca : ca // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,site: null == site ? _self.site : site // ignore: cast_nullable_to_non_nullable
as String,connectTo: freezed == connectTo ? _self.connectTo : connectTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
