// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'traffic_sample.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TrafficSample {

 DateTime get time; double get messagesIn; double get messagesOut; double get framesIn; double get framesOut;/// Bytes per second.
 double get dataIn; double get dataOut;
/// Create a copy of TrafficSample
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrafficSampleCopyWith<TrafficSample> get copyWith => _$TrafficSampleCopyWithImpl<TrafficSample>(this as TrafficSample, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TrafficSample;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrafficSample&&(identical(other.time, _this.time) || other.time == _this.time)&&(identical(other.messagesIn, _this.messagesIn) || other.messagesIn == _this.messagesIn)&&(identical(other.messagesOut, _this.messagesOut) || other.messagesOut == _this.messagesOut)&&(identical(other.framesIn, _this.framesIn) || other.framesIn == _this.framesIn)&&(identical(other.framesOut, _this.framesOut) || other.framesOut == _this.framesOut)&&(identical(other.dataIn, _this.dataIn) || other.dataIn == _this.dataIn)&&(identical(other.dataOut, _this.dataOut) || other.dataOut == _this.dataOut));
}


@override
int get hashCode {
  final _this = this as TrafficSample;
  return Object.hash(runtimeType,_this.time,_this.messagesIn,_this.messagesOut,_this.framesIn,_this.framesOut,_this.dataIn,_this.dataOut);
}

@override
String toString() {
  final _this = this as TrafficSample;
  return 'TrafficSample(time: ${_this.time}, messagesIn: ${_this.messagesIn}, messagesOut: ${_this.messagesOut}, framesIn: ${_this.framesIn}, framesOut: ${_this.framesOut}, dataIn: ${_this.dataIn}, dataOut: ${_this.dataOut})';
}


}

/// @nodoc
abstract mixin class $TrafficSampleCopyWith<$Res>  {
  factory $TrafficSampleCopyWith(TrafficSample value, $Res Function(TrafficSample) _then) = _$TrafficSampleCopyWithImpl;
@useResult
$Res call({
 DateTime time, double messagesIn, double messagesOut, double framesIn, double framesOut, double dataIn, double dataOut
});




}
/// @nodoc
class _$TrafficSampleCopyWithImpl<$Res>
    implements $TrafficSampleCopyWith<$Res> {
  _$TrafficSampleCopyWithImpl(this._self, this._then);

  final TrafficSample _self;
  final $Res Function(TrafficSample) _then;

/// Create a copy of TrafficSample
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? messagesIn = null,Object? messagesOut = null,Object? framesIn = null,Object? framesOut = null,Object? dataIn = null,Object? dataOut = null,}) {
  return _then(TrafficSample(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,messagesIn: null == messagesIn ? _self.messagesIn : messagesIn // ignore: cast_nullable_to_non_nullable
as double,messagesOut: null == messagesOut ? _self.messagesOut : messagesOut // ignore: cast_nullable_to_non_nullable
as double,framesIn: null == framesIn ? _self.framesIn : framesIn // ignore: cast_nullable_to_non_nullable
as double,framesOut: null == framesOut ? _self.framesOut : framesOut // ignore: cast_nullable_to_non_nullable
as double,dataIn: null == dataIn ? _self.dataIn : dataIn // ignore: cast_nullable_to_non_nullable
as double,dataOut: null == dataOut ? _self.dataOut : dataOut // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}



/// @nodoc


class _TrafficSample implements TrafficSample {
  const _TrafficSample({required this.time, this.messagesIn = 0, this.messagesOut = 0, this.framesIn = 0, this.framesOut = 0, this.dataIn = 0, this.dataOut = 0});
  

@override final  DateTime time;
@override@JsonKey() final  double messagesIn;
@override@JsonKey() final  double messagesOut;
@override@JsonKey() final  double framesIn;
@override@JsonKey() final  double framesOut;
/// Bytes per second.
@override@JsonKey() final  double dataIn;
@override@JsonKey() final  double dataOut;

/// Create a copy of TrafficSample
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TrafficSampleCopyWith<_TrafficSample> get copyWith => __$TrafficSampleCopyWithImpl<_TrafficSample>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TrafficSample&&(identical(other.time, time) || other.time == time)&&(identical(other.messagesIn, messagesIn) || other.messagesIn == messagesIn)&&(identical(other.messagesOut, messagesOut) || other.messagesOut == messagesOut)&&(identical(other.framesIn, framesIn) || other.framesIn == framesIn)&&(identical(other.framesOut, framesOut) || other.framesOut == framesOut)&&(identical(other.dataIn, dataIn) || other.dataIn == dataIn)&&(identical(other.dataOut, dataOut) || other.dataOut == dataOut));
}


@override
int get hashCode {
    return Object.hash(runtimeType,time,messagesIn,messagesOut,framesIn,framesOut,dataIn,dataOut);
}

@override
String toString() {
    return 'TrafficSample(time: $time, messagesIn: $messagesIn, messagesOut: $messagesOut, framesIn: $framesIn, framesOut: $framesOut, dataIn: $dataIn, dataOut: $dataOut)';
}


}

/// @nodoc
abstract mixin class _$TrafficSampleCopyWith<$Res> implements $TrafficSampleCopyWith<$Res> {
  factory _$TrafficSampleCopyWith(_TrafficSample value, $Res Function(_TrafficSample) _then) = __$TrafficSampleCopyWithImpl;
@override @useResult
$Res call({
 DateTime time, double messagesIn, double messagesOut, double framesIn, double framesOut, double dataIn, double dataOut
});




}
/// @nodoc
class __$TrafficSampleCopyWithImpl<$Res>
    implements _$TrafficSampleCopyWith<$Res> {
  __$TrafficSampleCopyWithImpl(this._self, this._then);

  final _TrafficSample _self;
  final $Res Function(_TrafficSample) _then;

/// Create a copy of TrafficSample
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? messagesIn = null,Object? messagesOut = null,Object? framesIn = null,Object? framesOut = null,Object? dataIn = null,Object? dataOut = null,}) {
  return _then(_TrafficSample(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,messagesIn: null == messagesIn ? _self.messagesIn : messagesIn // ignore: cast_nullable_to_non_nullable
as double,messagesOut: null == messagesOut ? _self.messagesOut : messagesOut // ignore: cast_nullable_to_non_nullable
as double,framesIn: null == framesIn ? _self.framesIn : framesIn // ignore: cast_nullable_to_non_nullable
as double,framesOut: null == framesOut ? _self.framesOut : framesOut // ignore: cast_nullable_to_non_nullable
as double,dataIn: null == dataIn ? _self.dataIn : dataIn // ignore: cast_nullable_to_non_nullable
as double,dataOut: null == dataOut ? _self.dataOut : dataOut // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
