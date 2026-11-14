// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'discovery_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DiscoveryState {

 bool get open; bool get scanning; bool get ended; int get scan; IMap<String, FoundGateway> get found; IMap<String, CaPin> get pins; String? get trustPending; String? get trustRefused; String? get picked; String? get network; String? get subnet; String? get range; String? get rangePort; bool get probing;
/// Create a copy of DiscoveryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiscoveryStateCopyWith<DiscoveryState> get copyWith => _$DiscoveryStateCopyWithImpl<DiscoveryState>(this as DiscoveryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as DiscoveryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscoveryState&&(identical(other.open, _this.open) || other.open == _this.open)&&(identical(other.scanning, _this.scanning) || other.scanning == _this.scanning)&&(identical(other.ended, _this.ended) || other.ended == _this.ended)&&(identical(other.scan, _this.scan) || other.scan == _this.scan)&&(identical(other.found, _this.found) || other.found == _this.found)&&(identical(other.pins, _this.pins) || other.pins == _this.pins)&&(identical(other.trustPending, _this.trustPending) || other.trustPending == _this.trustPending)&&(identical(other.trustRefused, _this.trustRefused) || other.trustRefused == _this.trustRefused)&&(identical(other.picked, _this.picked) || other.picked == _this.picked)&&(identical(other.network, _this.network) || other.network == _this.network)&&(identical(other.subnet, _this.subnet) || other.subnet == _this.subnet)&&(identical(other.range, _this.range) || other.range == _this.range)&&(identical(other.rangePort, _this.rangePort) || other.rangePort == _this.rangePort)&&(identical(other.probing, _this.probing) || other.probing == _this.probing));
}


@override
int get hashCode {
  final _this = this as DiscoveryState;
  return Object.hash(runtimeType,_this.open,_this.scanning,_this.ended,_this.scan,_this.found,_this.pins,_this.trustPending,_this.trustRefused,_this.picked,_this.network,_this.subnet,_this.range,_this.rangePort,_this.probing);
}

@override
String toString() {
  final _this = this as DiscoveryState;
  return 'DiscoveryState(open: ${_this.open}, scanning: ${_this.scanning}, ended: ${_this.ended}, scan: ${_this.scan}, found: ${_this.found}, pins: ${_this.pins}, trustPending: ${_this.trustPending}, trustRefused: ${_this.trustRefused}, picked: ${_this.picked}, network: ${_this.network}, subnet: ${_this.subnet}, range: ${_this.range}, rangePort: ${_this.rangePort}, probing: ${_this.probing})';
}


}

/// @nodoc
abstract mixin class $DiscoveryStateCopyWith<$Res>  {
  factory $DiscoveryStateCopyWith(DiscoveryState value, $Res Function(DiscoveryState) _then) = _$DiscoveryStateCopyWithImpl;
@useResult
$Res call({
 bool open, bool scanning, bool ended, int scan, IMap<String, FoundGateway> found, IMap<String, CaPin> pins, String? trustPending, String? trustRefused, String? picked, String? network, String? subnet, String? range, String? rangePort, bool probing
});




}
/// @nodoc
class _$DiscoveryStateCopyWithImpl<$Res>
    implements $DiscoveryStateCopyWith<$Res> {
  _$DiscoveryStateCopyWithImpl(this._self, this._then);

  final DiscoveryState _self;
  final $Res Function(DiscoveryState) _then;

/// Create a copy of DiscoveryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? open = null,Object? scanning = null,Object? ended = null,Object? scan = null,Object? found = null,Object? pins = null,Object? trustPending = freezed,Object? trustRefused = freezed,Object? picked = freezed,Object? network = freezed,Object? subnet = freezed,Object? range = freezed,Object? rangePort = freezed,Object? probing = null,}) {
  return _then(DiscoveryState(
open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,scanning: null == scanning ? _self.scanning : scanning // ignore: cast_nullable_to_non_nullable
as bool,ended: null == ended ? _self.ended : ended // ignore: cast_nullable_to_non_nullable
as bool,scan: null == scan ? _self.scan : scan // ignore: cast_nullable_to_non_nullable
as int,found: null == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as IMap<String, FoundGateway>,pins: null == pins ? _self.pins : pins // ignore: cast_nullable_to_non_nullable
as IMap<String, CaPin>,trustPending: freezed == trustPending ? _self.trustPending : trustPending // ignore: cast_nullable_to_non_nullable
as String?,trustRefused: freezed == trustRefused ? _self.trustRefused : trustRefused // ignore: cast_nullable_to_non_nullable
as String?,picked: freezed == picked ? _self.picked : picked // ignore: cast_nullable_to_non_nullable
as String?,network: freezed == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as String?,subnet: freezed == subnet ? _self.subnet : subnet // ignore: cast_nullable_to_non_nullable
as String?,range: freezed == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String?,rangePort: freezed == rangePort ? _self.rangePort : rangePort // ignore: cast_nullable_to_non_nullable
as String?,probing: null == probing ? _self.probing : probing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _DiscoveryState implements DiscoveryState {
  const _DiscoveryState({this.open = false, this.scanning = false, this.ended = false, this.scan = 0, this.found = const IMapConst({}), this.pins = const IMapConst({}), this.trustPending, this.trustRefused, this.picked, this.network, this.subnet, this.range, this.rangePort, this.probing = false});
  

@override@JsonKey() final  bool open;
@override@JsonKey() final  bool scanning;
@override@JsonKey() final  bool ended;
@override@JsonKey() final  int scan;
@override@JsonKey() final  IMap<String, FoundGateway> found;
@override@JsonKey() final  IMap<String, CaPin> pins;
@override final  String? trustPending;
@override final  String? trustRefused;
@override final  String? picked;
@override final  String? network;
@override final  String? subnet;
@override final  String? range;
@override final  String? rangePort;
@override@JsonKey() final  bool probing;

/// Create a copy of DiscoveryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiscoveryStateCopyWith<_DiscoveryState> get copyWith => __$DiscoveryStateCopyWithImpl<_DiscoveryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiscoveryState&&(identical(other.open, open) || other.open == open)&&(identical(other.scanning, scanning) || other.scanning == scanning)&&(identical(other.ended, ended) || other.ended == ended)&&(identical(other.scan, scan) || other.scan == scan)&&(identical(other.found, found) || other.found == found)&&(identical(other.pins, pins) || other.pins == pins)&&(identical(other.trustPending, trustPending) || other.trustPending == trustPending)&&(identical(other.trustRefused, trustRefused) || other.trustRefused == trustRefused)&&(identical(other.picked, picked) || other.picked == picked)&&(identical(other.network, network) || other.network == network)&&(identical(other.subnet, subnet) || other.subnet == subnet)&&(identical(other.range, range) || other.range == range)&&(identical(other.rangePort, rangePort) || other.rangePort == rangePort)&&(identical(other.probing, probing) || other.probing == probing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,open,scanning,ended,scan,found,pins,trustPending,trustRefused,picked,network,subnet,range,rangePort,probing);
}

@override
String toString() {
    return 'DiscoveryState(open: $open, scanning: $scanning, ended: $ended, scan: $scan, found: $found, pins: $pins, trustPending: $trustPending, trustRefused: $trustRefused, picked: $picked, network: $network, subnet: $subnet, range: $range, rangePort: $rangePort, probing: $probing)';
}


}

/// @nodoc
abstract mixin class _$DiscoveryStateCopyWith<$Res> implements $DiscoveryStateCopyWith<$Res> {
  factory _$DiscoveryStateCopyWith(_DiscoveryState value, $Res Function(_DiscoveryState) _then) = __$DiscoveryStateCopyWithImpl;
@override @useResult
$Res call({
 bool open, bool scanning, bool ended, int scan, IMap<String, FoundGateway> found, IMap<String, CaPin> pins, String? trustPending, String? trustRefused, String? picked, String? network, String? subnet, String? range, String? rangePort, bool probing
});




}
/// @nodoc
class __$DiscoveryStateCopyWithImpl<$Res>
    implements _$DiscoveryStateCopyWith<$Res> {
  __$DiscoveryStateCopyWithImpl(this._self, this._then);

  final _DiscoveryState _self;
  final $Res Function(_DiscoveryState) _then;

/// Create a copy of DiscoveryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? open = null,Object? scanning = null,Object? ended = null,Object? scan = null,Object? found = null,Object? pins = null,Object? trustPending = freezed,Object? trustRefused = freezed,Object? picked = freezed,Object? network = freezed,Object? subnet = freezed,Object? range = freezed,Object? rangePort = freezed,Object? probing = null,}) {
  return _then(_DiscoveryState(
open: null == open ? _self.open : open // ignore: cast_nullable_to_non_nullable
as bool,scanning: null == scanning ? _self.scanning : scanning // ignore: cast_nullable_to_non_nullable
as bool,ended: null == ended ? _self.ended : ended // ignore: cast_nullable_to_non_nullable
as bool,scan: null == scan ? _self.scan : scan // ignore: cast_nullable_to_non_nullable
as int,found: null == found ? _self.found : found // ignore: cast_nullable_to_non_nullable
as IMap<String, FoundGateway>,pins: null == pins ? _self.pins : pins // ignore: cast_nullable_to_non_nullable
as IMap<String, CaPin>,trustPending: freezed == trustPending ? _self.trustPending : trustPending // ignore: cast_nullable_to_non_nullable
as String?,trustRefused: freezed == trustRefused ? _self.trustRefused : trustRefused // ignore: cast_nullable_to_non_nullable
as String?,picked: freezed == picked ? _self.picked : picked // ignore: cast_nullable_to_non_nullable
as String?,network: freezed == network ? _self.network : network // ignore: cast_nullable_to_non_nullable
as String?,subnet: freezed == subnet ? _self.subnet : subnet // ignore: cast_nullable_to_non_nullable
as String?,range: freezed == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String?,rangePort: freezed == rangePort ? _self.rangePort : rangePort // ignore: cast_nullable_to_non_nullable
as String?,probing: null == probing ? _self.probing : probing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
