// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SystemState {

 IList<String> get log; String? get logLevel; String? get filter;
/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemStateCopyWith<SystemState> get copyWith => _$SystemStateCopyWithImpl<SystemState>(this as SystemState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemState&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel)&&(identical(other.filter, filter) || other.filter == filter));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(log),logLevel,filter);

@override
String toString() {
  return 'SystemState(log: $log, logLevel: $logLevel, filter: $filter)';
}


}

/// @nodoc
abstract mixin class $SystemStateCopyWith<$Res>  {
  factory $SystemStateCopyWith(SystemState value, $Res Function(SystemState) _then) = _$SystemStateCopyWithImpl;
@useResult
$Res call({
 IList<String> log, String? logLevel, String? filter
});




}
/// @nodoc
class _$SystemStateCopyWithImpl<$Res>
    implements $SystemStateCopyWith<$Res> {
  _$SystemStateCopyWithImpl(this._self, this._then);

  final SystemState _self;
  final $Res Function(SystemState) _then;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? log = null,Object? logLevel = freezed,Object? filter = freezed,}) {
  return _then(_self.copyWith(
log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as String?,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _SystemState implements SystemState {
  const _SystemState({this.log = const IListConst([]), this.logLevel, this.filter});
  

@override@JsonKey() final  IList<String> log;
@override final  String? logLevel;
@override final  String? filter;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SystemStateCopyWith<_SystemState> get copyWith => __$SystemStateCopyWithImpl<_SystemState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SystemState&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.logLevel, logLevel) || other.logLevel == logLevel)&&(identical(other.filter, filter) || other.filter == filter));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(log),logLevel,filter);

@override
String toString() {
  return 'SystemState(log: $log, logLevel: $logLevel, filter: $filter)';
}


}

/// @nodoc
abstract mixin class _$SystemStateCopyWith<$Res> implements $SystemStateCopyWith<$Res> {
  factory _$SystemStateCopyWith(_SystemState value, $Res Function(_SystemState) _then) = __$SystemStateCopyWithImpl;
@override @useResult
$Res call({
 IList<String> log, String? logLevel, String? filter
});




}
/// @nodoc
class __$SystemStateCopyWithImpl<$Res>
    implements _$SystemStateCopyWith<$Res> {
  __$SystemStateCopyWithImpl(this._self, this._then);

  final _SystemState _self;
  final $Res Function(_SystemState) _then;

/// Create a copy of SystemState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? log = null,Object? logLevel = freezed,Object? filter = freezed,}) {
  return _then(_SystemState(
log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,logLevel: freezed == logLevel ? _self.logLevel : logLevel // ignore: cast_nullable_to_non_nullable
as String?,filter: freezed == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
