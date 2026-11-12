// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SystemState {

 IList<LogLine> get log; String? get logLevel; String? get filter; String get tab; String get measure; String? get source; int get lines; bool get auto; bool get shown; String? get logError; IList<TrafficSample> get samples; String? get trafficRoot; IList<ProfileInfo> get profiles; String? get profilesNote; int? get aclSeen; IMap<String, String> get about; IMap<String, String> get units; String? get around; HistWindow? get trafficWindow;
/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemStateCopyWith<SystemState> get copyWith => _$SystemStateCopyWithImpl<SystemState>(this as SystemState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SystemState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemState&&const DeepCollectionEquality().equals(other.log, _this.log)&&(identical(other.logLevel, _this.logLevel) || other.logLevel == _this.logLevel)&&(identical(other.filter, _this.filter) || other.filter == _this.filter)&&(identical(other.tab, _this.tab) || other.tab == _this.tab)&&(identical(other.measure, _this.measure) || other.measure == _this.measure)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.lines, _this.lines) || other.lines == _this.lines)&&(identical(other.auto, _this.auto) || other.auto == _this.auto)&&(identical(other.shown, _this.shown) || other.shown == _this.shown)&&(identical(other.logError, _this.logError) || other.logError == _this.logError)&&const DeepCollectionEquality().equals(other.samples, _this.samples)&&(identical(other.trafficRoot, _this.trafficRoot) || other.trafficRoot == _this.trafficRoot)&&const DeepCollectionEquality().equals(other.profiles, _this.profiles)&&(identical(other.profilesNote, _this.profilesNote) || other.profilesNote == _this.profilesNote)&&(identical(other.aclSeen, _this.aclSeen) || other.aclSeen == _this.aclSeen)&&(identical(other.about, _this.about) || other.about == _this.about)&&(identical(other.units, _this.units) || other.units == _this.units)&&(identical(other.around, _this.around) || other.around == _this.around)&&(identical(other.trafficWindow, _this.trafficWindow) || other.trafficWindow == _this.trafficWindow));
}


@override
int get hashCode {
  final _this = this as SystemState;
  return Object.hashAll([runtimeType,const DeepCollectionEquality().hash(_this.log),_this.logLevel,_this.filter,_this.tab,_this.measure,_this.source,_this.lines,_this.auto,_this.shown,_this.logError,const DeepCollectionEquality().hash(_this.samples),_this.trafficRoot,const DeepCollectionEquality().hash(_this.profiles),_this.profilesNote,_this.aclSeen,_this.about,_this.units,_this.around,_this.trafficWindow]);
}

@override
String toString() {
  final _this = this as SystemState;
  return 'SystemState(log: ${_this.log}, logLevel: ${_this.logLevel}, filter: ${_this.filter}, tab: ${_this.tab}, measure: ${_this.measure}, source: ${_this.source}, lines: ${_this.lines}, auto: ${_this.auto}, shown: ${_this.shown}, logError: ${_this.logError}, samples: ${_this.samples}, trafficRoot: ${_this.trafficRoot}, profiles: ${_this.profiles}, profilesNote: ${_this.profilesNote}, aclSeen: ${_this.aclSeen}, about: ${_this.about}, units: ${_this.units}, around: ${_this.around}, trafficWindow: ${_this.trafficWindow})';
}


}

/// @nodoc
abstract mixin class $SystemStateCopyWith<$Res>  {
  factory $SystemStateCopyWith(SystemState value, $Res Function(SystemState) _then) = _$SystemStateCopyWithImpl;
@useResult
$Res call({
 IList<LogLine> log, String? logLevel, String? filter, String tab, String measure, String? source, int lines, bool auto, bool shown, String? logError, IList<TrafficSample> samples, String? trafficRoot, IList<ProfileInfo> profiles, String? profilesNote, int? aclSeen, IMap<String, String> about, IMap<String, String> units, String? around, HistWindow? trafficWindow
});


$HistWindowCopyWith<$Res>? get trafficWindow;

}
/// @nodoc
class _$SystemStateCopyWithImpl<$Res>
    implements $SystemStateCopyWith<$Res> {
  _$SystemStateCopyWithImpl(this._self, this._then);

  final SystemState _self;
  final $Res Function(SystemState) _then;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? log = null,Object? logLevel = freezed,Object? filter = freezed,Object? tab = null,Object? measure = null,Object? source = freezed,Object? lines = null,Object? auto = null,Object? shown = null,Object? logError = freezed,Object? samples = null,Object? trafficRoot = freezed,Object? profiles = null,Object? profilesNote = freezed,Object? aclSeen = freezed,Object? about = null,Object? units = null,Object? around = freezed,Object? trafficWindow = freezed,}) {
  return _then(SystemState(
log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<LogLine>,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as String?,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,measure: null == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as int,auto: null == auto ? _self.auto : auto // ignore: cast_nullable_to_non_nullable
as bool,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,logError: freezed == logError ? _self.logError : logError // ignore: cast_nullable_to_non_nullable
as String?,samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as IList<TrafficSample>,trafficRoot: freezed == trafficRoot ? _self.trafficRoot : trafficRoot // ignore: cast_nullable_to_non_nullable
as String?,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as IList<ProfileInfo>,profilesNote: freezed == profilesNote ? _self.profilesNote : profilesNote // ignore: cast_nullable_to_non_nullable
as String?,aclSeen: freezed == aclSeen ? _self.aclSeen : aclSeen // ignore: cast_nullable_to_non_nullable
as int?,about: null == about ? _self.about : about // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,around: freezed == around ? _self.around : around // ignore: cast_nullable_to_non_nullable
as String?,trafficWindow: freezed == trafficWindow ? _self.trafficWindow : trafficWindow // ignore: cast_nullable_to_non_nullable
as HistWindow?,
  ));
}
/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get trafficWindow {
    if (_self.trafficWindow == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.trafficWindow!, (value) {
    return _then(_self.copyWith(trafficWindow: value));
  });
}
}



/// @nodoc


class _SystemState implements SystemState {
  const _SystemState({this.log = const IListConst([]), this.logLevel, this.filter, this.tab = 'overview', this.measure = 'messages', this.source, this.lines = 200, this.auto = true, this.shown = false, this.logError, this.samples = const IListConst([]), this.trafficRoot, this.profiles = const IListConst([]), this.profilesNote, this.aclSeen, this.about = const IMapConst({}), this.units = const IMapConst({}), this.around, this.trafficWindow});
  

@override@JsonKey() final  IList<LogLine> log;
@override final  String? logLevel;
@override final  String? filter;
@override@JsonKey() final  String tab;
@override@JsonKey() final  String measure;
@override final  String? source;
@override@JsonKey() final  int lines;
@override@JsonKey() final  bool auto;
@override@JsonKey() final  bool shown;
@override final  String? logError;
@override@JsonKey() final  IList<TrafficSample> samples;
@override final  String? trafficRoot;
@override@JsonKey() final  IList<ProfileInfo> profiles;
@override final  String? profilesNote;
@override final  int? aclSeen;
@override@JsonKey() final  IMap<String, String> about;
@override@JsonKey() final  IMap<String, String> units;
@override final  String? around;
@override final  HistWindow? trafficWindow;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SystemStateCopyWith<_SystemState> get copyWith => __$SystemStateCopyWithImpl<_SystemState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SystemState&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel)&&(identical(other.filter, filter) || other.filter == filter)&&(identical(other.tab, tab) || other.tab == tab)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.source, source) || other.source == source)&&(identical(other.lines, lines) || other.lines == lines)&&(identical(other.auto, auto) || other.auto == auto)&&(identical(other.shown, shown) || other.shown == shown)&&(identical(other.logError, logError) || other.logError == logError)&&const DeepCollectionEquality().equals(other.samples, samples)&&(identical(other.trafficRoot, trafficRoot) || other.trafficRoot == trafficRoot)&&const DeepCollectionEquality().equals(other.profiles, profiles)&&(identical(other.profilesNote, profilesNote) || other.profilesNote == profilesNote)&&(identical(other.aclSeen, aclSeen) || other.aclSeen == aclSeen)&&(identical(other.about, about) || other.about == about)&&(identical(other.units, units) || other.units == units)&&(identical(other.around, around) || other.around == around)&&(identical(other.trafficWindow, trafficWindow) || other.trafficWindow == trafficWindow));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,const DeepCollectionEquality().hash(log),logLevel,filter,tab,measure,source,lines,auto,shown,logError,const DeepCollectionEquality().hash(samples),trafficRoot,const DeepCollectionEquality().hash(profiles),profilesNote,aclSeen,about,units,around,trafficWindow]);
}

@override
String toString() {
    return 'SystemState(log: $log, logLevel: $logLevel, filter: $filter, tab: $tab, measure: $measure, source: $source, lines: $lines, auto: $auto, shown: $shown, logError: $logError, samples: $samples, trafficRoot: $trafficRoot, profiles: $profiles, profilesNote: $profilesNote, aclSeen: $aclSeen, about: $about, units: $units, around: $around, trafficWindow: $trafficWindow)';
}


}

/// @nodoc
abstract mixin class _$SystemStateCopyWith<$Res> implements $SystemStateCopyWith<$Res> {
  factory _$SystemStateCopyWith(_SystemState value, $Res Function(_SystemState) _then) = __$SystemStateCopyWithImpl;
@override @useResult
$Res call({
 IList<LogLine> log, String? logLevel, String? filter, String tab, String measure, String? source, int lines, bool auto, bool shown, String? logError, IList<TrafficSample> samples, String? trafficRoot, IList<ProfileInfo> profiles, String? profilesNote, int? aclSeen, IMap<String, String> about, IMap<String, String> units, String? around, HistWindow? trafficWindow
});


@override $HistWindowCopyWith<$Res>? get trafficWindow;

}
/// @nodoc
class __$SystemStateCopyWithImpl<$Res>
    implements _$SystemStateCopyWith<$Res> {
  __$SystemStateCopyWithImpl(this._self, this._then);

  final _SystemState _self;
  final $Res Function(_SystemState) _then;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? log = null,Object? logLevel = freezed,Object? filter = freezed,Object? tab = null,Object? measure = null,Object? source = freezed,Object? lines = null,Object? auto = null,Object? shown = null,Object? logError = freezed,Object? samples = null,Object? trafficRoot = freezed,Object? profiles = null,Object? profilesNote = freezed,Object? aclSeen = freezed,Object? about = null,Object? units = null,Object? around = freezed,Object? trafficWindow = freezed,}) {
  return _then(_SystemState(
log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<LogLine>,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as String?,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,tab: null == tab ? _self.tab : tab // ignore: cast_nullable_to_non_nullable
as String,measure: null == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as int,auto: null == auto ? _self.auto : auto // ignore: cast_nullable_to_non_nullable
as bool,shown: null == shown ? _self.shown : shown // ignore: cast_nullable_to_non_nullable
as bool,logError: freezed == logError ? _self.logError : logError // ignore: cast_nullable_to_non_nullable
as String?,samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as IList<TrafficSample>,trafficRoot: freezed == trafficRoot ? _self.trafficRoot : trafficRoot // ignore: cast_nullable_to_non_nullable
as String?,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as IList<ProfileInfo>,profilesNote: freezed == profilesNote ? _self.profilesNote : profilesNote // ignore: cast_nullable_to_non_nullable
as String?,aclSeen: freezed == aclSeen ? _self.aclSeen : aclSeen // ignore: cast_nullable_to_non_nullable
as int?,about: null == about ? _self.about : about // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,around: freezed == around ? _self.around : around // ignore: cast_nullable_to_non_nullable
as String?,trafficWindow: freezed == trafficWindow ? _self.trafficWindow : trafficWindow // ignore: cast_nullable_to_non_nullable
as HistWindow?,
  ));
}

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get trafficWindow {
    if (_self.trafficWindow == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.trafficWindow!, (value) {
    return _then(_self.copyWith(trafficWindow: value));
  });
}
}

// dart format on
