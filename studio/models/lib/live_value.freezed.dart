// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_value.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveValue {

 DateTime get time; Object? get value; Quality get quality;
/// Create a copy of LiveValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveValueCopyWith<LiveValue> get copyWith => _$LiveValueCopyWithImpl<LiveValue>(this as LiveValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LiveValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveValue&&(identical(other.time, _this.time) || other.time == _this.time)&&const DeepCollectionEquality().equals(other.value, _this.value)&&(identical(other.quality, _this.quality) || other.quality == _this.quality));
}


@override
int get hashCode {
  final _this = this as LiveValue;
  return Object.hash(runtimeType,_this.time,const DeepCollectionEquality().hash(_this.value),_this.quality);
}

@override
String toString() {
  final _this = this as LiveValue;
  return 'LiveValue(time: ${_this.time}, value: ${_this.value}, quality: ${_this.quality})';
}


}

/// @nodoc
abstract mixin class $LiveValueCopyWith<$Res>  {
  factory $LiveValueCopyWith(LiveValue value, $Res Function(LiveValue) _then) = _$LiveValueCopyWithImpl;
@useResult
$Res call({
 DateTime time, Object? value, Quality quality
});




}
/// @nodoc
class _$LiveValueCopyWithImpl<$Res>
    implements $LiveValueCopyWith<$Res> {
  _$LiveValueCopyWithImpl(this._self, this._then);

  final LiveValue _self;
  final $Res Function(LiveValue) _then;

/// Create a copy of LiveValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? time = null,Object? value = freezed,Object? quality = null,}) {
  return _then(LiveValue(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,value: freezed == value ? _self.value : value ,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as Quality,
  ));
}

}



/// @nodoc


class _LiveValue implements LiveValue {
  const _LiveValue({required this.time, this.value, this.quality = Quality.good});
  

@override final  DateTime time;
@override final  Object? value;
@override@JsonKey() final  Quality quality;

/// Create a copy of LiveValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveValueCopyWith<_LiveValue> get copyWith => __$LiveValueCopyWithImpl<_LiveValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveValue&&(identical(other.time, time) || other.time == time)&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.quality, quality) || other.quality == quality));
}


@override
int get hashCode {
    return Object.hash(runtimeType,time,const DeepCollectionEquality().hash(value),quality);
}

@override
String toString() {
    return 'LiveValue(time: $time, value: $value, quality: $quality)';
}


}

/// @nodoc
abstract mixin class _$LiveValueCopyWith<$Res> implements $LiveValueCopyWith<$Res> {
  factory _$LiveValueCopyWith(_LiveValue value, $Res Function(_LiveValue) _then) = __$LiveValueCopyWithImpl;
@override @useResult
$Res call({
 DateTime time, Object? value, Quality quality
});




}
/// @nodoc
class __$LiveValueCopyWithImpl<$Res>
    implements _$LiveValueCopyWith<$Res> {
  __$LiveValueCopyWithImpl(this._self, this._then);

  final _LiveValue _self;
  final $Res Function(_LiveValue) _then;

/// Create a copy of LiveValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? time = null,Object? value = freezed,Object? quality = null,}) {
  return _then(_LiveValue(
time: null == time ? _self.time : time // ignore: cast_nullable_to_non_nullable
as DateTime,value: freezed == value ? _self.value : value ,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as Quality,
  ));
}


}

// dart format on
