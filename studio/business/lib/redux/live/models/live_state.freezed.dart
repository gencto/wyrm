// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveState {

 IMap<String, LiveValue> get values; ISet<String> get watched;
/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveStateCopyWith<LiveState> get copyWith => _$LiveStateCopyWithImpl<LiveState>(this as LiveState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveState&&(identical(other.values, values) || other.values == values)&&const DeepCollectionEquality().equals(other.watched, watched));
}


@override
int get hashCode => Object.hash(runtimeType,values,const DeepCollectionEquality().hash(watched));

@override
String toString() {
  return 'LiveState(values: $values, watched: $watched)';
}


}

/// @nodoc
abstract mixin class $LiveStateCopyWith<$Res>  {
  factory $LiveStateCopyWith(LiveState value, $Res Function(LiveState) _then) = _$LiveStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, LiveValue> values, ISet<String> watched
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
@pragma('vm:prefer-inline') @override $Res call({Object? values = null,Object? watched = null,}) {
  return _then(_self.copyWith(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as ISet<String>,
  ));
}

}



/// @nodoc


class _LiveState implements LiveState {
  const _LiveState({this.values = const IMapConst({}), this.watched = const ISetConst({})});
  

@override@JsonKey() final  IMap<String, LiveValue> values;
@override@JsonKey() final  ISet<String> watched;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveStateCopyWith<_LiveState> get copyWith => __$LiveStateCopyWithImpl<_LiveState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveState&&(identical(other.values, values) || other.values == values)&&const DeepCollectionEquality().equals(other.watched, watched));
}


@override
int get hashCode => Object.hash(runtimeType,values,const DeepCollectionEquality().hash(watched));

@override
String toString() {
  return 'LiveState(values: $values, watched: $watched)';
}


}

/// @nodoc
abstract mixin class _$LiveStateCopyWith<$Res> implements $LiveStateCopyWith<$Res> {
  factory _$LiveStateCopyWith(_LiveState value, $Res Function(_LiveState) _then) = __$LiveStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, LiveValue> values, ISet<String> watched
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
@override @pragma('vm:prefer-inline') $Res call({Object? values = null,Object? watched = null,}) {
  return _then(_LiveState(
values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as IMap<String, LiveValue>,watched: null == watched ? _self.watched : watched // ignore: cast_nullable_to_non_nullable
as ISet<String>,
  ));
}


}

// dart format on
