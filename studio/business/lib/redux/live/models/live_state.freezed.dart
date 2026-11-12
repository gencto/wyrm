// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveState {

 IMap<String, LiveValue> get values; IMap<String, int> get watched; IMap<String, String> get failed;
/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveStateCopyWith<LiveState> get copyWith => _$LiveStateCopyWithImpl<LiveState>(this as LiveState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LiveState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveState&&(identical(other.values, _this.values) || other.values == _this.values)&&(identical(other.watched, _this.watched) || other.watched == _this.watched)&&(identical(other.failed, _this.failed) || other.failed == _this.failed));
}


@override
int get hashCode {
  final _this = this as LiveState;
  return Object.hash(runtimeType,_this.values,_this.watched,_this.failed);
}

@override
String toString() {
  final _this = this as LiveState;
  return 'LiveState(values: ${_this.values}, watched: ${_this.watched}, failed: ${_this.failed})';
}


}

/// @nodoc
abstract mixin class $LiveStateCopyWith<$Res>  {
  factory $LiveStateCopyWith(LiveState value, $Res Function(LiveState) _then) = _$LiveStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, LiveValue> values, IMap<String, int> watched, IMap<String, String> failed
});




}
/// @nodoc
class _$LiveStateCopyWithImpl<$Res>
    implements $LiveStateCopyWith<$Res> {
  _$LiveStateCopyWithImpl(this._self, this._then);

  final LiveState _self;
  final $Res Function(LiveState) _then;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? values = null,Object? watched = null,Object? failed = null,}) {
  return _then(LiveState(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}

}



/// @nodoc


class _LiveState implements LiveState {
  const _LiveState({this.values = const IMapConst({}), this.watched = const IMapConst({}), this.failed = const IMapConst({})});
  

@override@JsonKey() final  IMap<String, LiveValue> values;
@override@JsonKey() final  IMap<String, int> watched;
@override@JsonKey() final  IMap<String, String> failed;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveStateCopyWith<_LiveState> get copyWith => __$LiveStateCopyWithImpl<_LiveState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveState&&(identical(other.values, values) || other.values == values)&&(identical(other.watched, watched) || other.watched == watched)&&(identical(other.failed, failed) || other.failed == failed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,values,watched,failed);
}

@override
String toString() {
    return 'LiveState(values: $values, watched: $watched, failed: $failed)';
}


}

/// @nodoc
abstract mixin class _$LiveStateCopyWith<$Res> implements $LiveStateCopyWith<$Res> {
  factory _$LiveStateCopyWith(_LiveState value, $Res Function(_LiveState) _then) = __$LiveStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, LiveValue> values, IMap<String, int> watched, IMap<String, String> failed
});




}
/// @nodoc
class __$LiveStateCopyWithImpl<$Res>
    implements _$LiveStateCopyWith<$Res> {
  __$LiveStateCopyWithImpl(this._self, this._then);

  final _LiveState _self;
  final $Res Function(_LiveState) _then;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? values = null,Object? watched = null,Object? failed = null,}) {
  return _then(_LiveState(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as IMap<String, int>,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as IMap<String, String>,
  ));
}


}

// dart format on
