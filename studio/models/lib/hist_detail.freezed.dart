// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hist_detail.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistDetail {

 DateTime get from; DateTime get to; String get step; IMap<String, IList<HistPoint>> get points; IMap<String, IList<HistPoint>> get low; IMap<String, IList<HistPoint>> get high;
/// Create a copy of HistDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistDetailCopyWith<HistDetail> get copyWith => _$HistDetailCopyWithImpl<HistDetail>(this as HistDetail, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as HistDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistDetail&&(identical(other.from, _this.from) || other.from == _this.from)&&(identical(other.to, _this.to) || other.to == _this.to)&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.points, _this.points) || other.points == _this.points)&&(identical(other.low, _this.low) || other.low == _this.low)&&(identical(other.high, _this.high) || other.high == _this.high));
}


@override
int get hashCode {
  final _this = this as HistDetail;
  return Object.hash(runtimeType,_this.from,_this.to,_this.step,_this.points,_this.low,_this.high);
}

@override
String toString() {
  final _this = this as HistDetail;
  return 'HistDetail(from: ${_this.from}, to: ${_this.to}, step: ${_this.step}, points: ${_this.points}, low: ${_this.low}, high: ${_this.high})';
}


}

/// @nodoc
abstract mixin class $HistDetailCopyWith<$Res>  {
  factory $HistDetailCopyWith(HistDetail value, $Res Function(HistDetail) _then) = _$HistDetailCopyWithImpl;
@useResult
$Res call({
 DateTime from, DateTime to, String step, IMap<String, IList<HistPoint>> points, IMap<String, IList<HistPoint>> low, IMap<String, IList<HistPoint>> high
});




}
/// @nodoc
class _$HistDetailCopyWithImpl<$Res>
    implements $HistDetailCopyWith<$Res> {
  _$HistDetailCopyWithImpl(this._self, this._then);

  final HistDetail _self;
  final $Res Function(HistDetail) _then;

/// Create a copy of HistDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? from = null,Object? to = null,Object? step = null,Object? points = null,Object? low = null,Object? high = null,}) {
  return _then(HistDetail(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as DateTime,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as DateTime,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,high: null == high ? _self.high : high // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,
  ));
}

}



/// @nodoc


class _HistDetail implements HistDetail {
  const _HistDetail({required this.from, required this.to, required this.step, this.points = const IMapConst({}), this.low = const IMapConst({}), this.high = const IMapConst({})});
  

@override final  DateTime from;
@override final  DateTime to;
@override final  String step;
@override@JsonKey() final  IMap<String, IList<HistPoint>> points;
@override@JsonKey() final  IMap<String, IList<HistPoint>> low;
@override@JsonKey() final  IMap<String, IList<HistPoint>> high;

/// Create a copy of HistDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistDetailCopyWith<_HistDetail> get copyWith => __$HistDetailCopyWithImpl<_HistDetail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistDetail&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&(identical(other.step, step) || other.step == step)&&(identical(other.points, points) || other.points == points)&&(identical(other.low, low) || other.low == low)&&(identical(other.high, high) || other.high == high));
}


@override
int get hashCode {
    return Object.hash(runtimeType,from,to,step,points,low,high);
}

@override
String toString() {
    return 'HistDetail(from: $from, to: $to, step: $step, points: $points, low: $low, high: $high)';
}


}

/// @nodoc
abstract mixin class _$HistDetailCopyWith<$Res> implements $HistDetailCopyWith<$Res> {
  factory _$HistDetailCopyWith(_HistDetail value, $Res Function(_HistDetail) _then) = __$HistDetailCopyWithImpl;
@override @useResult
$Res call({
 DateTime from, DateTime to, String step, IMap<String, IList<HistPoint>> points, IMap<String, IList<HistPoint>> low, IMap<String, IList<HistPoint>> high
});




}
/// @nodoc
class __$HistDetailCopyWithImpl<$Res>
    implements _$HistDetailCopyWith<$Res> {
  __$HistDetailCopyWithImpl(this._self, this._then);

  final _HistDetail _self;
  final $Res Function(_HistDetail) _then;

/// Create a copy of HistDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? from = null,Object? to = null,Object? step = null,Object? points = null,Object? low = null,Object? high = null,}) {
  return _then(_HistDetail(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as DateTime,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as DateTime,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as String,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,high: null == high ? _self.high : high // ignore: cast_nullable_to_non_nullable
as IMap<String, IList<HistPoint>>,
  ));
}


}

// dart format on
