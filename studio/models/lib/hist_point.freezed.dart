// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'hist_point.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$HistPoint {

 DateTime get time;/// A number when the value is one (a bool as 0/1), else null.
 num? get value;/// The value as text.
 String get text;/// `good`, `uncertain`, `bad`; null for a rollup row.
 String? get quality;
/// Create a copy of HistPoint
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistPointCopyWith<HistPoint> get copyWith => _$HistPointCopyWithImpl<HistPoint>(this as HistPoint, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HistPoint&&(identical(other.time, time) || other.time == time)&&(identical(other.value, value) || other.value == value)&&(identical(other.text, text) || other.text == text)&&(identical(other.quality, quality) || other.quality == quality));
}


@override
int get hashCode => Object.hash(runtimeType,time,value,text,quality);

@override
String toString() {
  return 'HistPoint(time: $time, value: $value, text: $text, quality: $quality)';
}


}

/// @nodoc
abstract mixin class $HistPointCopyWith<$Res>  {
  factory $HistPointCopyWith(HistPoint value, $Res Function(HistPoint) _then) = _$HistPointCopyWithImpl;
@useResult
$Res call({
 DateTime time, num? value, String text, String? quality
});




}
/// @nodoc
class _$HistPointCopyWithImpl<$Res>
    implements $HistPointCopyWith<$Res> {
  _$HistPointCopyWithImpl(this._self, this._then);

  final HistPoint _self;
  final $Res Function(HistPoint) _then;

/// Create a copy of HistPoint
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? value = freezed,Object? text = null,Object? quality = freezed,}) {
  return _then(_self.copyWith(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as num?,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _HistPoint implements HistPoint {
  const _HistPoint({required this.time, this.value, this.text = '', this.quality});
  

@override final  DateTime time;
/// A number when the value is one (a bool as 0/1), else null.
@override final  num? value;
/// The value as text.
@override@JsonKey() final  String text;
/// `good`, `uncertain`, `bad`; null for a rollup row.
@override final  String? quality;

/// Create a copy of HistPoint
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistPointCopyWith<_HistPoint> get copyWith => __$HistPointCopyWithImpl<_HistPoint>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HistPoint&&(identical(other.time, time) || other.time == time)&&(identical(other.value, value) || other.value == value)&&(identical(other.text, text) || other.text == text)&&(identical(other.quality, quality) || other.quality == quality));
}


@override
int get hashCode => Object.hash(runtimeType,time,value,text,quality);

@override
String toString() {
  return 'HistPoint(time: $time, value: $value, text: $text, quality: $quality)';
}


}

/// @nodoc
abstract mixin class _$HistPointCopyWith<$Res> implements $HistPointCopyWith<$Res> {
  factory _$HistPointCopyWith(_HistPoint value, $Res Function(_HistPoint) _then) = __$HistPointCopyWithImpl;
@override @useResult
$Res call({
 DateTime time, num? value, String text, String? quality
});




}
/// @nodoc
class __$HistPointCopyWithImpl<$Res>
    implements _$HistPointCopyWith<$Res> {
  __$HistPointCopyWithImpl(this._self, this._then);

  final _HistPoint _self;
  final $Res Function(_HistPoint) _then;

/// Create a copy of HistPoint
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? value = freezed,Object? text = null,Object? quality = freezed,}) {
  return _then(_HistPoint(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as num?,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
