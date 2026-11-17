// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'clock_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClockState {

 DateTime? get now;
/// Create a copy of ClockState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClockStateCopyWith<ClockState> get copyWith => _$ClockStateCopyWithImpl<ClockState>(this as ClockState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClockState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClockState&&(identical(other.now, _this.now) || other.now == _this.now));
}


@override
int get hashCode {
  final _this = this as ClockState;
  return Object.hash(runtimeType,_this.now);
}

@override
String toString() {
  final _this = this as ClockState;
  return 'ClockState(now: ${_this.now})';
}


}

/// @nodoc
abstract mixin class $ClockStateCopyWith<$Res>  {
  factory $ClockStateCopyWith(ClockState value, $Res Function(ClockState) _then) = _$ClockStateCopyWithImpl;
@useResult
$Res call({
 DateTime? now
});




}
/// @nodoc
class _$ClockStateCopyWithImpl<$Res>
    implements $ClockStateCopyWith<$Res> {
  _$ClockStateCopyWithImpl(this._self, this._then);

  final ClockState _self;
  final $Res Function(ClockState) _then;

/// Create a copy of ClockState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? now = freezed,}) {
  return _then(ClockState(
now: freezed == now ? _self.now : now // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}



/// @nodoc


class _ClockState implements ClockState {
  const _ClockState({this.now});
  

@override final  DateTime? now;

/// Create a copy of ClockState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClockStateCopyWith<_ClockState> get copyWith => __$ClockStateCopyWithImpl<_ClockState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClockState&&(identical(other.now, now) || other.now == now));
}


@override
int get hashCode {
    return Object.hash(runtimeType,now);
}

@override
String toString() {
    return 'ClockState(now: $now)';
}


}

/// @nodoc
abstract mixin class _$ClockStateCopyWith<$Res> implements $ClockStateCopyWith<$Res> {
  factory _$ClockStateCopyWith(_ClockState value, $Res Function(_ClockState) _then) = __$ClockStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime? now
});




}
/// @nodoc
class __$ClockStateCopyWithImpl<$Res>
    implements _$ClockStateCopyWith<$Res> {
  __$ClockStateCopyWithImpl(this._self, this._then);

  final _ClockState _self;
  final $Res Function(_ClockState) _then;

/// Create a copy of ClockState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? now = freezed,}) {
  return _then(_ClockState(
now: freezed == now ? _self.now : now // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
