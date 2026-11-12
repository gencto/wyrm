// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'historian_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistorianState {

 IList<WatchGroup> get groups; String? get selected; String get range; IMap<String, IList<HistPoint>> get series; IMap<String, String> get stats; IList<String> get points; LiveSet? get follow;
/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistorianStateCopyWith<HistorianState> get copyWith => _$HistorianStateCopyWithImpl<HistorianState>(this as HistorianState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistorianState&&const DeepCollectionEquality().equals(other.groups, groups)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.range, range) || other.range == range)&&(identical(other.series, series) || other.series == series)&&(identical(other.stats, stats) || other.stats == stats)&&const DeepCollectionEquality().equals(other.points, points)&&(identical(other.follow, follow) || other.follow == follow));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(groups),selected,range,series,stats,const DeepCollectionEquality().hash(points),follow);

@override
String toString() {
  return 'HistorianState(groups: $groups, selected: $selected, range: $range, series: $series, stats: $stats, points: $points, follow: $follow)';
}


}

/// @nodoc
abstract mixin class $HistorianStateCopyWith<$Res>  {
  factory $HistorianStateCopyWith(HistorianState value, $Res Function(HistorianState) _then) = _$HistorianStateCopyWithImpl;
@useResult
$Res call({
 IList<WatchGroup> groups, String? selected, String range, IMap<String, IList<HistPoint>> series, IMap<String, String> stats, IList<String> points, LiveSet? follow
});


$LiveSetCopyWith<$Res>? get follow;

}
/// @nodoc
class _$HistorianStateCopyWithImpl<$Res>
    implements $HistorianStateCopyWith<$Res> {
  _$HistorianStateCopyWithImpl(this._self, this._then);

  final HistorianState _self;
  final $Res Function(HistorianState) _then;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? groups = null,Object? selected = freezed,Object? range = null,Object? series = null,Object? stats = null,Object? points = null,Object? follow = freezed,}) {
  return _then(_self.copyWith(
groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as IList<WatchGroup>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String,series: null == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,stats: null == stats ? _self.stats : stats // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IList<String>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,
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
}
}



/// @nodoc


class _HistorianState implements HistorianState {
  const _HistorianState({this.groups = const IListConst([]), this.selected, this.range = '24h', this.series = const IMapConst({}), this.stats = const IMapConst({}), this.points = const IListConst([]), this.follow});
  

@override@JsonKey() final  IList<WatchGroup> groups;
@override final  String? selected;
@override@JsonKey() final  String range;
@override@JsonKey() final  IMap<String, IList<HistPoint>> series;
@override@JsonKey() final  IMap<String, String> stats;
@override@JsonKey() final  IList<String> points;
@override final  LiveSet? follow;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistorianStateCopyWith<_HistorianState> get copyWith => __$HistorianStateCopyWithImpl<_HistorianState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistorianState&&const DeepCollectionEquality().equals(other.groups, groups)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.range, range) || other.range == range)&&(identical(other.series, series) || other.series == series)&&(identical(other.stats, stats) || other.stats == stats)&&const DeepCollectionEquality().equals(other.points, points)&&(identical(other.follow, follow) || other.follow == follow));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(groups),selected,range,series,stats,const DeepCollectionEquality().hash(points),follow);

@override
String toString() {
  return 'HistorianState(groups: $groups, selected: $selected, range: $range, series: $series, stats: $stats, points: $points, follow: $follow)';
}


}

/// @nodoc
abstract mixin class _$HistorianStateCopyWith<$Res> implements $HistorianStateCopyWith<$Res> {
  factory _$HistorianStateCopyWith(_HistorianState value, $Res Function(_HistorianState) _then) = __$HistorianStateCopyWithImpl;
@override @useResult
$Res call({
 IList<WatchGroup> groups, String? selected, String range, IMap<String, IList<HistPoint>> series, IMap<String, String> stats, IList<String> points, LiveSet? follow
});


@override $LiveSetCopyWith<$Res>? get follow;

}
/// @nodoc
class __$HistorianStateCopyWithImpl<$Res>
    implements _$HistorianStateCopyWith<$Res> {
  __$HistorianStateCopyWithImpl(this._self, this._then);

  final _HistorianState _self;
  final $Res Function(_HistorianState) _then;

/// Create a copy of HistorianState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? groups = null,Object? selected = freezed,Object? range = null,Object? series = null,Object? stats = null,Object? points = null,Object? follow = freezed,}) {
  return _then(_HistorianState(
groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as IList<WatchGroup>,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as String?,range: null == range ? _self.range : range // ignore: cast_nullable_to_non_nullable
as String,series: null == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,stats: null == stats ? _self.stats : stats // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IList<String>,follow: freezed == follow ? _self.follow : follow // ignore: cast_nullable_to_non_nullable
as LiveSet?,
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
}
}

// dart format on
