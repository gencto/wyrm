// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'broker_self_update.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BrokerSelfUpdate {

/// What runs now; empty before it arrived.
 String get version;/// The release the channel offers; empty when none.
 String get latest; SelfUpdateState get state; SelfUpdateMode get mode;/// `update_last`: the last update's facts.
 UpdateLast get last;
/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrokerSelfUpdateCopyWith<BrokerSelfUpdate> get copyWith => _$BrokerSelfUpdateCopyWithImpl<BrokerSelfUpdate>(this as BrokerSelfUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BrokerSelfUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrokerSelfUpdate&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.latest, _this.latest) || other.latest == _this.latest)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.last, _this.last) || other.last == _this.last));
}


@override
int get hashCode {
  final _this = this as BrokerSelfUpdate;
  return Object.hash(runtimeType,_this.version,_this.latest,_this.state,_this.mode,_this.last);
}

@override
String toString() {
  final _this = this as BrokerSelfUpdate;
  return 'BrokerSelfUpdate(version: ${_this.version}, latest: ${_this.latest}, state: ${_this.state}, mode: ${_this.mode}, last: ${_this.last})';
}


}

/// @nodoc
abstract mixin class $BrokerSelfUpdateCopyWith<$Res>  {
  factory $BrokerSelfUpdateCopyWith(BrokerSelfUpdate value, $Res Function(BrokerSelfUpdate) _then) = _$BrokerSelfUpdateCopyWithImpl;
@useResult
$Res call({
 String version, String latest, SelfUpdateState state, SelfUpdateMode mode, UpdateLast last
});


$UpdateLastCopyWith<$Res> get last;

}
/// @nodoc
class _$BrokerSelfUpdateCopyWithImpl<$Res>
    implements $BrokerSelfUpdateCopyWith<$Res> {
  _$BrokerSelfUpdateCopyWithImpl(this._self, this._then);

  final BrokerSelfUpdate _self;
  final $Res Function(BrokerSelfUpdate) _then;

/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? latest = null,Object? state = null,Object? mode = null,Object? last = null,}) {
  return _then(BrokerSelfUpdate(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SelfUpdateState,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as SelfUpdateMode,last: null == last ? _self.last : last // ignore: cast_nullable_to_non_nullable
as UpdateLast,
  ));
}
/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateLastCopyWith<$Res> get last {
  
  return $UpdateLastCopyWith<$Res>(_self.last, (value) {
    return _then(_self.copyWith(last: value));
  });
}
}



/// @nodoc


class _BrokerSelfUpdate extends BrokerSelfUpdate {
  const _BrokerSelfUpdate({this.version = '', this.latest = '', this.state = SelfUpdateState.none, this.mode = SelfUpdateMode.self, this.last = const UpdateLast()}): super._();
  

/// What runs now; empty before it arrived.
@override@JsonKey() final  String version;
/// The release the channel offers; empty when none.
@override@JsonKey() final  String latest;
@override@JsonKey() final  SelfUpdateState state;
@override@JsonKey() final  SelfUpdateMode mode;
/// `update_last`: the last update's facts.
@override@JsonKey() final  UpdateLast last;

/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrokerSelfUpdateCopyWith<_BrokerSelfUpdate> get copyWith => __$BrokerSelfUpdateCopyWithImpl<_BrokerSelfUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrokerSelfUpdate&&(identical(other.version, version) || other.version == version)&&(identical(other.latest, latest) || other.latest == latest)&&(identical(other.state, state) || other.state == state)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.last, last) || other.last == last));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version,latest,state,mode,last);
}

@override
String toString() {
    return 'BrokerSelfUpdate(version: $version, latest: $latest, state: $state, mode: $mode, last: $last)';
}


}

/// @nodoc
abstract mixin class _$BrokerSelfUpdateCopyWith<$Res> implements $BrokerSelfUpdateCopyWith<$Res> {
  factory _$BrokerSelfUpdateCopyWith(_BrokerSelfUpdate value, $Res Function(_BrokerSelfUpdate) _then) = __$BrokerSelfUpdateCopyWithImpl;
@override @useResult
$Res call({
 String version, String latest, SelfUpdateState state, SelfUpdateMode mode, UpdateLast last
});


@override $UpdateLastCopyWith<$Res> get last;

}
/// @nodoc
class __$BrokerSelfUpdateCopyWithImpl<$Res>
    implements _$BrokerSelfUpdateCopyWith<$Res> {
  __$BrokerSelfUpdateCopyWithImpl(this._self, this._then);

  final _BrokerSelfUpdate _self;
  final $Res Function(_BrokerSelfUpdate) _then;

/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? latest = null,Object? state = null,Object? mode = null,Object? last = null,}) {
  return _then(_BrokerSelfUpdate(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SelfUpdateState,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as SelfUpdateMode,last: null == last ? _self.last : last // ignore: cast_nullable_to_non_nullable
as UpdateLast,
  ));
}

/// Create a copy of BrokerSelfUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateLastCopyWith<$Res> get last {
  
  return $UpdateLastCopyWith<$Res>(_self.last, (value) {
    return _then(_self.copyWith(last: value));
  });
}
}

/// @nodoc
mixin _$UpdateLast {

/// The version updated from and to.
 String? get from; String? get to;/// Why it rolled back.
 String? get reason;/// Seconds the broker was down.
 String? get downS;/// Links back after the restart, of [links], in [backS] seconds.
 String? get linksBack; String? get links; String? get backS;/// Until when a roll back is offered.
 String? get rollbackUntil;
/// Create a copy of UpdateLast
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateLastCopyWith<UpdateLast> get copyWith => _$UpdateLastCopyWithImpl<UpdateLast>(this as UpdateLast, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateLast;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateLast&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.to, _this.to) || other.to == _this.to)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.downS, _this.downS) || other.downS == _this.downS)&&(identical(other.linksBack, _this.linksBack) || other.linksBack == _this.linksBack)&&(identical(other.links, _this.links) || other.links == _this.links)&&(identical(other.backS, _this.backS) || other.backS == _this.backS)&&(identical(other.rollbackUntil, _this.rollbackUntil) || other.rollbackUntil == _this.rollbackUntil));
}


@override
int get hashCode {
  final _this = this as UpdateLast;
  return Object.hash(runtimeType,_this.from,_this.to,_this.reason,_this.downS,_this.linksBack,_this.links,_this.backS,_this.rollbackUntil);
}

@override
String toString() {
  final _this = this as UpdateLast;
  return 'UpdateLast(from: ${_this.from}, to: ${_this.to}, reason: ${_this.reason}, downS: ${_this.downS}, linksBack: ${_this.linksBack}, links: ${_this.links}, backS: ${_this.backS}, rollbackUntil: ${_this.rollbackUntil})';
}


}

/// @nodoc
abstract mixin class $UpdateLastCopyWith<$Res>  {
  factory $UpdateLastCopyWith(UpdateLast value, $Res Function(UpdateLast) _then) = _$UpdateLastCopyWithImpl;
@useResult
$Res call({
 String? from, String? to, String? reason, String? downS, String? linksBack, String? links, String? backS, String? rollbackUntil
});




}
/// @nodoc
class _$UpdateLastCopyWithImpl<$Res>
    implements $UpdateLastCopyWith<$Res> {
  _$UpdateLastCopyWithImpl(this._self, this._then);

  final UpdateLast _self;
  final $Res Function(UpdateLast) _then;

/// Create a copy of UpdateLast
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? from = freezed,Object? to = freezed,Object? reason = freezed,Object? downS = freezed,Object? linksBack = freezed,Object? links = freezed,Object? backS = freezed,Object? rollbackUntil = freezed,}) {
  return _then(UpdateLast(
from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,downS: freezed == downS ? _self.downS : downS // ignore: cast_nullable_to_non_nullable
as String?,linksBack: freezed == linksBack ? _self.linksBack : linksBack // ignore: cast_nullable_to_non_nullable
as String?,links: freezed == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as String?,backS: freezed == backS ? _self.backS : backS // ignore: cast_nullable_to_non_nullable
as String?,rollbackUntil: freezed == rollbackUntil ? _self.rollbackUntil : rollbackUntil // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _UpdateLast implements UpdateLast {
  const _UpdateLast({this.from, this.to, this.reason, this.downS, this.linksBack, this.links, this.backS, this.rollbackUntil});
  

/// The version updated from and to.
@override final  String? from;
@override final  String? to;
/// Why it rolled back.
@override final  String? reason;
/// Seconds the broker was down.
@override final  String? downS;
/// Links back after the restart, of [links], in [backS] seconds.
@override final  String? linksBack;
@override final  String? links;
@override final  String? backS;
/// Until when a roll back is offered.
@override final  String? rollbackUntil;

/// Create a copy of UpdateLast
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateLastCopyWith<_UpdateLast> get copyWith => __$UpdateLastCopyWithImpl<_UpdateLast>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateLast&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.downS, downS) || other.downS == downS)&&(identical(other.linksBack, linksBack) || other.linksBack == linksBack)&&(identical(other.links, links) || other.links == links)&&(identical(other.backS, backS) || other.backS == backS)&&(identical(other.rollbackUntil, rollbackUntil) || other.rollbackUntil == rollbackUntil));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,to,reason,downS,linksBack,links,backS,rollbackUntil);
}

@override
String toString() {
    return 'UpdateLast(from: $from, to: $to, reason: $reason, downS: $downS, linksBack: $linksBack, links: $links, backS: $backS, rollbackUntil: $rollbackUntil)';
}


}

/// @nodoc
abstract mixin class _$UpdateLastCopyWith<$Res> implements $UpdateLastCopyWith<$Res> {
  factory _$UpdateLastCopyWith(_UpdateLast value, $Res Function(_UpdateLast) _then) = __$UpdateLastCopyWithImpl;
@override @useResult
$Res call({
 String? from, String? to, String? reason, String? downS, String? linksBack, String? links, String? backS, String? rollbackUntil
});




}
/// @nodoc
class __$UpdateLastCopyWithImpl<$Res>
    implements _$UpdateLastCopyWith<$Res> {
  __$UpdateLastCopyWithImpl(this._self, this._then);

  final _UpdateLast _self;
  final $Res Function(_UpdateLast) _then;

/// Create a copy of UpdateLast
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? from = freezed,Object? to = freezed,Object? reason = freezed,Object? downS = freezed,Object? linksBack = freezed,Object? links = freezed,Object? backS = freezed,Object? rollbackUntil = freezed,}) {
  return _then(_UpdateLast(
from: freezed == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String?,to: freezed == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,downS: freezed == downS ? _self.downS : downS // ignore: cast_nullable_to_non_nullable
as String?,linksBack: freezed == linksBack ? _self.linksBack : linksBack // ignore: cast_nullable_to_non_nullable
as String?,links: freezed == links ? _self.links : links // ignore: cast_nullable_to_non_nullable
as String?,backS: freezed == backS ? _self.backS : backS // ignore: cast_nullable_to_non_nullable
as String?,rollbackUntil: freezed == rollbackUntil ? _self.rollbackUntil : rollbackUntil // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
