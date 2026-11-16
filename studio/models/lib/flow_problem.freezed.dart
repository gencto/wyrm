// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flow_problem.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FlowProblem {

 FlowProblemKind get kind;/// The broker's own words ([FlowProblemKind.broker]); null for the
/// editor's own problems, which `ui` says in its words.
 String? get message;/// The block it names; null when it names none.
 String? get block;
/// Create a copy of FlowProblem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowProblemCopyWith<FlowProblem> get copyWith => _$FlowProblemCopyWithImpl<FlowProblem>(this as FlowProblem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FlowProblem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlowProblem&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.block, _this.block) || other.block == _this.block));
}


@override
int get hashCode {
  final _this = this as FlowProblem;
  return Object.hash(runtimeType,_this.kind,_this.message,_this.block);
}

@override
String toString() {
  final _this = this as FlowProblem;
  return 'FlowProblem(kind: ${_this.kind}, message: ${_this.message}, block: ${_this.block})';
}


}

/// @nodoc
abstract mixin class $FlowProblemCopyWith<$Res>  {
  factory $FlowProblemCopyWith(FlowProblem value, $Res Function(FlowProblem) _then) = _$FlowProblemCopyWithImpl;
@useResult
$Res call({
 FlowProblemKind kind, String? message, String? block
});




}
/// @nodoc
class _$FlowProblemCopyWithImpl<$Res>
    implements $FlowProblemCopyWith<$Res> {
  _$FlowProblemCopyWithImpl(this._self, this._then);

  final FlowProblem _self;
  final $Res Function(FlowProblem) _then;

/// Create a copy of FlowProblem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? message = freezed,Object? block = freezed,}) {
  return _then(FlowProblem(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FlowProblemKind,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,block: freezed == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _FlowProblem implements FlowProblem {
  const _FlowProblem({required this.kind, this.message, this.block});
  

@override final  FlowProblemKind kind;
/// The broker's own words ([FlowProblemKind.broker]); null for the
/// editor's own problems, which `ui` says in its words.
@override final  String? message;
/// The block it names; null when it names none.
@override final  String? block;

/// Create a copy of FlowProblem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlowProblemCopyWith<_FlowProblem> get copyWith => __$FlowProblemCopyWithImpl<_FlowProblem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlowProblem&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.message, message) || other.message == message)&&(identical(other.block, block) || other.block == block));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,message,block);
}

@override
String toString() {
    return 'FlowProblem(kind: $kind, message: $message, block: $block)';
}


}

/// @nodoc
abstract mixin class _$FlowProblemCopyWith<$Res> implements $FlowProblemCopyWith<$Res> {
  factory _$FlowProblemCopyWith(_FlowProblem value, $Res Function(_FlowProblem) _then) = __$FlowProblemCopyWithImpl;
@override @useResult
$Res call({
 FlowProblemKind kind, String? message, String? block
});




}
/// @nodoc
class __$FlowProblemCopyWithImpl<$Res>
    implements _$FlowProblemCopyWith<$Res> {
  __$FlowProblemCopyWithImpl(this._self, this._then);

  final _FlowProblem _self;
  final $Res Function(_FlowProblem) _then;

/// Create a copy of FlowProblem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? message = freezed,Object? block = freezed,}) {
  return _then(_FlowProblem(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FlowProblemKind,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,block: freezed == block ? _self.block : block // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
