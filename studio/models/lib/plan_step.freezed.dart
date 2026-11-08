// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_step.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlanStep {

/// `set` or `invoke`.
 String get op; String get key; String? get action; IMap<String, Object?> get args;/// `read`, `write` or `config`.
 String get level; bool get approval; String? get reason;
/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanStepCopyWith<PlanStep> get copyWith => _$PlanStepCopyWithImpl<PlanStep>(this as PlanStep, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanStep&&(identical(other.op, op) || other.op == op)&&(identical(other.key, key) || other.key == key)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args)&&(identical(other.level, level) || other.level == level)&&(identical(other.approval, approval) || other.approval == approval)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,op,key,action,args,level,approval,reason);

@override
String toString() {
  return 'PlanStep(op: $op, key: $key, action: $action, args: $args, level: $level, approval: $approval, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $PlanStepCopyWith<$Res>  {
  factory $PlanStepCopyWith(PlanStep value, $Res Function(PlanStep) _then) = _$PlanStepCopyWithImpl;
@useResult
$Res call({
 String op, String key, String? action, IMap<String, Object?> args, String level, bool approval, String? reason
});




}
/// @nodoc
class _$PlanStepCopyWithImpl<$Res>
    implements $PlanStepCopyWith<$Res> {
  _$PlanStepCopyWithImpl(this._self, this._then);

  final PlanStep _self;
  final $Res Function(PlanStep) _then;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? op = null,Object? key = null,Object? action = freezed,Object? args = null,Object? level = null,Object? approval = null,Object? reason = freezed,}) {
  return _then(_self.copyWith(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _PlanStep implements PlanStep {
  const _PlanStep({required this.op, required this.key, this.action, this.args = const IMapConst({}), this.level = 'write', this.approval = false, this.reason});
  

/// `set` or `invoke`.
@override final  String op;
@override final  String key;
@override final  String? action;
@override@JsonKey() final  IMap<String, Object?> args;
/// `read`, `write` or `config`.
@override@JsonKey() final  String level;
@override@JsonKey() final  bool approval;
@override final  String? reason;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanStepCopyWith<_PlanStep> get copyWith => __$PlanStepCopyWithImpl<_PlanStep>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanStep&&(identical(other.op, op) || other.op == op)&&(identical(other.key, key) || other.key == key)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args)&&(identical(other.level, level) || other.level == level)&&(identical(other.approval, approval) || other.approval == approval)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,op,key,action,args,level,approval,reason);

@override
String toString() {
  return 'PlanStep(op: $op, key: $key, action: $action, args: $args, level: $level, approval: $approval, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$PlanStepCopyWith<$Res> implements $PlanStepCopyWith<$Res> {
  factory _$PlanStepCopyWith(_PlanStep value, $Res Function(_PlanStep) _then) = __$PlanStepCopyWithImpl;
@override @useResult
$Res call({
 String op, String key, String? action, IMap<String, Object?> args, String level, bool approval, String? reason
});




}
/// @nodoc
class __$PlanStepCopyWithImpl<$Res>
    implements _$PlanStepCopyWith<$Res> {
  __$PlanStepCopyWithImpl(this._self, this._then);

  final _PlanStep _self;
  final $Res Function(_PlanStep) _then;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? op = null,Object? key = null,Object? action = freezed,Object? args = null,Object? level = null,Object? approval = null,Object? reason = freezed,}) {
  return _then(_PlanStep(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
