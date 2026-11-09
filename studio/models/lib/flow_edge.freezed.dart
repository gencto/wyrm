// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_edge.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowEdge {

 String get from; String get fromPort; String get to; String get toPort;
/// Create a copy of FlowEdge
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowEdgeCopyWith<FlowEdge> get copyWith => _$FlowEdgeCopyWithImpl<FlowEdge>(this as FlowEdge, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowEdge&&(identical(other.from, from) || other.from == from)&&(identical(other.fromPort, fromPort) || other.fromPort == fromPort)&&(identical(other.to, to) || other.to == to)&&(identical(other.toPort, toPort) || other.toPort == toPort));
}


@override
int get hashCode => Object.hash(runtimeType,from,fromPort,to,toPort);

@override
String toString() {
  return 'FlowEdge(from: $from, fromPort: $fromPort, to: $to, toPort: $toPort)';
}


}

/// @nodoc
abstract mixin class $FlowEdgeCopyWith<$Res>  {
  factory $FlowEdgeCopyWith(FlowEdge value, $Res Function(FlowEdge) _then) = _$FlowEdgeCopyWithImpl;
@useResult
$Res call({
 String from, String fromPort, String to, String toPort
});




}
/// @nodoc
class _$FlowEdgeCopyWithImpl<$Res>
    implements $FlowEdgeCopyWith<$Res> {
  _$FlowEdgeCopyWithImpl(this._self, this._then);

  final FlowEdge _self;
  final $Res Function(FlowEdge) _then;

/// Create a copy of FlowEdge
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? from = null,Object? fromPort = null,Object? to = null,Object? toPort = null,}) {
  return _then(_self.copyWith(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fromPort: null == fromPort ? _self.fromPort : fromPort // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,toPort: null == toPort ? _self.toPort : toPort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc


class _FlowEdge implements FlowEdge {
  const _FlowEdge({required this.from, required this.fromPort, required this.to, required this.toPort});
  

@override final  String from;
@override final  String fromPort;
@override final  String to;
@override final  String toPort;

/// Create a copy of FlowEdge
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowEdgeCopyWith<_FlowEdge> get copyWith => __$FlowEdgeCopyWithImpl<_FlowEdge>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowEdge&&(identical(other.from, from) || other.from == from)&&(identical(other.fromPort, fromPort) || other.fromPort == fromPort)&&(identical(other.to, to) || other.to == to)&&(identical(other.toPort, toPort) || other.toPort == toPort));
}


@override
int get hashCode => Object.hash(runtimeType,from,fromPort,to,toPort);

@override
String toString() {
  return 'FlowEdge(from: $from, fromPort: $fromPort, to: $to, toPort: $toPort)';
}


}

/// @nodoc
abstract mixin class _$FlowEdgeCopyWith<$Res> implements $FlowEdgeCopyWith<$Res> {
  factory _$FlowEdgeCopyWith(_FlowEdge value, $Res Function(_FlowEdge) _then) = __$FlowEdgeCopyWithImpl;
@override @useResult
$Res call({
 String from, String fromPort, String to, String toPort
});




}
/// @nodoc
class __$FlowEdgeCopyWithImpl<$Res>
    implements _$FlowEdgeCopyWith<$Res> {
  __$FlowEdgeCopyWithImpl(this._self, this._then);

  final _FlowEdge _self;
  final $Res Function(_FlowEdge) _then;

/// Create a copy of FlowEdge
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? from = null,Object? fromPort = null,Object? to = null,Object? toPort = null,}) {
  return _then(_FlowEdge(
from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as String,fromPort: null == fromPort ? _self.fromPort : fromPort // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as String,toPort: null == toPort ? _self.toPort : toPort // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
