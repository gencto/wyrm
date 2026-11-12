// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'historian_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistorianState {

 IList<WatchGroup> get groups; String? get selected; String get range; IMap<String, IList<HistPoint>> get series; IMap<String, String> get stats; IList<String> get points; LiveSet? get follow; HistWindow? get window; HistDetail? get detail; IMap<String, IList<HistPoint>> get low; IMap<String, IList<HistPoint>> get high; ISet<String> get hidden; int get trendGen; DateTime? get seriesAt;
/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistorianStateCopyWith<HistorianState> get copyWith => _$HistorianStateCopyWithImpl<HistorianState>(this as HistorianState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as HistorianState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistorianState&&const DeepCollectionEquality().equals(other.groups, _this.groups)&&(identical(other.selected, _this.selected) || other.selected == _this.selected)&&(identical(other.range, _this.range) || other.range == _this.range)&&(identical(other.series, _this.series) || other.series == _this.series)&&(identical(other.stats, _this.stats) || other.stats == _this.stats)&&const DeepCollectionEquality().equals(other.points, _this.points)&&(identical(other.follow, _this.follow) || other.follow == _this.follow)&&(identical(other.window, _this.window) || other.window == _this.window)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.low, _this.low) || other.low == _this.low)&&(identical(other.high, _this.high) || other.high == _this.high)&&const DeepCollectionEquality().equals(other.hidden, _this.hidden)&&(identical(other.trendGen, _this.trendGen) || other.trendGen == _this.trendGen)&&(identical(other.seriesAt, _this.seriesAt) || other.seriesAt == _this.seriesAt));
}


@override
int get hashCode {
  final _this = this as HistorianState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.groups),_this.selected,_this.range,_this.series,_this.stats,const DeepCollectionEquality().hash(_this.points),_this.follow,_this.window,_this.detail,_this.low,_this.high,const DeepCollectionEquality().hash(_this.hidden),_this.trendGen,_this.seriesAt);
}

@override
String toString() {
  final _this = this as HistorianState;
  return 'HistorianState(groups: ${_this.groups}, selected: ${_this.selected}, range: ${_this.range}, series: ${_this.series}, stats: ${_this.stats}, points: ${_this.points}, follow: ${_this.follow}, window: ${_this.window}, detail: ${_this.detail}, low: ${_this.low}, high: ${_this.high}, hidden: ${_this.hidden}, trendGen: ${_this.trendGen}, seriesAt: ${_this.seriesAt})';
}


}

/// @nodoc
abstract mixin class $HistorianStateCopyWith<$Res>  {
  factory $HistorianStateCopyWith(HistorianState value, $Res Function(HistorianState) _then) = _$HistorianStateCopyWithImpl;
@useResult
$Res call({
 IList<WatchGroup> groups, String? selected, String range, IMap<String, IList<HistPoint>> series, IMap<String, String> stats, IList<String> points, LiveSet? follow, HistWindow? window, HistDetail? detail, IMap<String, IList<HistPoint>> low, IMap<String, IList<HistPoint>> high, ISet<String> hidden, int trendGen, DateTime? seriesAt
});


$LiveSetCopyWith<$Res>? get follow;$HistWindowCopyWith<$Res>? get window;$HistDetailCopyWith<$Res>? get detail;

}
/// @nodoc
class _$HistorianStateCopyWithImpl<$Res>
    implements $HistorianStateCopyWith<$Res> {
  _$HistorianStateCopyWithImpl(this._self, this._then);

  final HistorianState _self;
  final $Res Function(HistorianState) _then;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? groups = null,Object? selected = freezed,Object? range = null,Object? series = null,Object? stats = null,Object? points = null,Object? follow = freezed,Object? window = freezed,Object? detail = freezed,Object? low = null,Object? high = null,Object? hidden = null,Object? trendGen = null,Object? seriesAt = freezed,}) {
  return _then(HistorianState(
groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as IList<WatchGroup>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String,series: null == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,stats: null == stats ? _self.stats : stats // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IList<String>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,window: freezed == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as HistWindow?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as HistDetail?,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,high: null == high ? _self.high : high // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as ISet<String>,trendGen: null == trendGen ? _self.trendGen : trendGen // ignore: cast_nullable_to_non_nullable
as int,seriesAt: freezed == seriesAt ? _self.seriesAt : seriesAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveSetCopyWith<$Res>? get follow {
    if (_self.follow == null) {
    return null;
  }

  return $LiveSetCopyWith<$Res>(_self.follow!, (value) {
    return _then(_self.copyWith(follow: value));
  });
}/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get window {
    if (_self.window == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.window!, (value) {
    return _then(_self.copyWith(window: value));
  });
}/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistDetailCopyWith<$Res>? get detail {
    if (_self.detail == null) {
    return null;
  }

  return $HistDetailCopyWith<$Res>(_self.detail!, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}



/// @nodoc


class _HistorianState implements HistorianState {
  const _HistorianState({this.groups = const IListConst([]), this.selected, this.range = '24h', this.series = const IMapConst({}), this.stats = const IMapConst({}), this.points = const IListConst([]), this.follow, this.window, this.detail, this.low = const IMapConst({}), this.high = const IMapConst({}), this.hidden = const ISetConst({}), this.trendGen = 0, this.seriesAt});
  

@override@JsonKey() final  IList<WatchGroup> groups;
@override final  String? selected;
@override@JsonKey() final  String range;
@override@JsonKey() final  IMap<String, IList<HistPoint>> series;
@override@JsonKey() final  IMap<String, String> stats;
@override@JsonKey() final  IList<String> points;
@override final  LiveSet? follow;
@override final  HistWindow? window;
@override final  HistDetail? detail;
@override@JsonKey() final  IMap<String, IList<HistPoint>> low;
@override@JsonKey() final  IMap<String, IList<HistPoint>> high;
@override@JsonKey() final  ISet<String> hidden;
@override@JsonKey() final  int trendGen;
@override final  DateTime? seriesAt;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistorianStateCopyWith<_HistorianState> get copyWith => __$HistorianStateCopyWithImpl<_HistorianState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistorianState&&const DeepCollectionEquality().equals(other.groups, groups)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.range, range) || other.range == range)&&(identical(other.series, series) || other.series == series)&&(identical(other.stats, stats) || other.stats == stats)&&const DeepCollectionEquality().equals(other.points, points)&&(identical(other.follow, follow) || other.follow == follow)&&(identical(other.window, window) || other.window == window)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.low, low) || other.low == low)&&(identical(other.high, high) || other.high == high)&&const DeepCollectionEquality().equals(other.hidden, hidden)&&(identical(other.trendGen, trendGen) || other.trendGen == trendGen)&&(identical(other.seriesAt, seriesAt) || other.seriesAt == seriesAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(groups),selected,range,series,stats,const DeepCollectionEquality().hash(points),follow,window,detail,low,high,const DeepCollectionEquality().hash(hidden),trendGen,seriesAt);
}

@override
String toString() {
    return 'HistorianState(groups: $groups, selected: $selected, range: $range, series: $series, stats: $stats, points: $points, follow: $follow, window: $window, detail: $detail, low: $low, high: $high, hidden: $hidden, trendGen: $trendGen, seriesAt: $seriesAt)';
}


}

/// @nodoc
abstract mixin class _$HistorianStateCopyWith<$Res> implements $HistorianStateCopyWith<$Res> {
  factory _$HistorianStateCopyWith(_HistorianState value, $Res Function(_HistorianState) _then) = __$HistorianStateCopyWithImpl;
@override @useResult
$Res call({
 IList<WatchGroup> groups, String? selected, String range, IMap<String, IList<HistPoint>> series, IMap<String, String> stats, IList<String> points, LiveSet? follow, HistWindow? window, HistDetail? detail, IMap<String, IList<HistPoint>> low, IMap<String, IList<HistPoint>> high, ISet<String> hidden, int trendGen, DateTime? seriesAt
});


@override $LiveSetCopyWith<$Res>? get follow;@override $HistWindowCopyWith<$Res>? get window;@override $HistDetailCopyWith<$Res>? get detail;

}
/// @nodoc
class __$HistorianStateCopyWithImpl<$Res>
    implements _$HistorianStateCopyWith<$Res> {
  __$HistorianStateCopyWithImpl(this._self, this._then);

  final _HistorianState _self;
  final $Res Function(_HistorianState) _then;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? groups = null,Object? selected = freezed,Object? range = null,Object? series = null,Object? stats = null,Object? points = null,Object? follow = freezed,Object? window = freezed,Object? detail = freezed,Object? low = null,Object? high = null,Object? hidden = null,Object? trendGen = null,Object? seriesAt = freezed,}) {
  return _then(_HistorianState(
groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as IList<WatchGroup>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String,series: null == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,stats: null == stats ? _self.stats : stats // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IList<String>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,window: freezed == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as HistWindow?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as HistDetail?,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,high: null == high ? _self.high : high // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,hidden: null == hidden ? _self.hidden : hidden // ignore: cast_nullable_to_non_nullable
as ISet<String>,trendGen: null == trendGen ? _self.trendGen : trendGen // ignore: cast_nullable_to_non_nullable
as int,seriesAt: freezed == seriesAt ? _self.seriesAt : seriesAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveSetCopyWith<$Res>? get follow {
    if (_self.follow == null) {
    return null;
  }

  return $LiveSetCopyWith<$Res>(_self.follow!, (value) {
    return _then(_self.copyWith(follow: value));
  });
}/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistWindowCopyWith<$Res>? get window {
    if (_self.window == null) {
    return null;
  }

  return $HistWindowCopyWith<$Res>(_self.window!, (value) {
    return _then(_self.copyWith(window: value));
  });
}/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$HistDetailCopyWith<$Res>? get detail {
    if (_self.detail == null) {
    return null;
  }

  return $HistDetailCopyWith<$Res>(_self.detail!, (value) {
    return _then(_self.copyWith(detail: value));
  });
}
}

// dart format on
