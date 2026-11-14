// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_step.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlanStep {

/// `set`, `invoke`, `wait`, `expect` or `sleep`.
 String get op;/// The node the step is about (empty for `sleep`).
 String get key;/// Its number in the plan, from 1.
 int get n; String? get action;/// `set`: `{value}`; `invoke`: its arguments; `expect`: the test
/// (`equals`, `min`/`max`, `changes`).
 IMap<String, Object?> get args;/// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
 double? get seconds;/// `read`, `write` or `config`.
 String get level;/// The step needs a human token.
 bool get approval;/// `now` (checked against the live tree) or `at_run`.
 String get check; String? get warn;/// The steps (by number) this one needs.
 IList<int> get after; String? get reason; StepResult? get result;
/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanStepCopyWith<PlanStep> get copyWith => _$PlanStepCopyWithImpl<PlanStep>(this as PlanStep, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanStep&&(identical(other.op, _this.op) || other.op == _this.op)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.n, _this.n) || other.n == _this.n)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.args, _this.args) || other.args == _this.args)&&(identical(other.seconds, _this.seconds) || other.seconds == _this.seconds)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.approval, _this.approval) || other.approval == _this.approval)&&(identical(other.check, _this.check) || other.check == _this.check)&&(identical(other.warn, _this.warn) || other.warn == _this.warn)&&const DeepCollectionEquality().equals(other.after, _this.after)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as PlanStep;
  return Object.hash(runtimeType,_this.op,_this.key,_this.n,_this.action,_this.args,_this.seconds,_this.level,_this.approval,_this.check,_this.warn,const DeepCollectionEquality().hash(_this.after),_this.reason,_this.result);
}

@override
String toString() {
  final _this = this as PlanStep;
  return 'PlanStep(op: ${_this.op}, key: ${_this.key}, n: ${_this.n}, action: ${_this.action}, args: ${_this.args}, seconds: ${_this.seconds}, level: ${_this.level}, approval: ${_this.approval}, check: ${_this.check}, warn: ${_this.warn}, after: ${_this.after}, reason: ${_this.reason}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $PlanStepCopyWith<$Res>  {
  factory $PlanStepCopyWith(PlanStep value, $Res Function(PlanStep) _then) = _$PlanStepCopyWithImpl;
@useResult
$Res call({
 String op, String key, int n, String? action, IMap<String, Object?> args, double? seconds, String level, bool approval, String check, String? warn, IList<int> after, String? reason, StepResult? result
});


$StepResultCopyWith<$Res>? get result;

}
/// @nodoc
class _$PlanStepCopyWithImpl<$Res>
    implements $PlanStepCopyWith<$Res> {
  _$PlanStepCopyWithImpl(this._self, this._then);

  final PlanStep _self;
  final $Res Function(PlanStep) _then;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? op = null,Object? key = null,Object? n = null,Object? action = freezed,Object? args = null,Object? seconds = freezed,Object? level = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? after = null,Object? reason = freezed,Object? result = freezed,}) {
  return _then(PlanStep(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as String,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as IList<int>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as StepResult?,
  ));
}
/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $StepResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}



/// @nodoc


class _PlanStep implements PlanStep {
  const _PlanStep({required this.op, required this.key, this.n = 0, this.action, this.args = const IMapConst({}), this.seconds, this.level = 'write', this.approval = false, this.check = 'now', this.warn, this.after = const IListConst([]), this.reason, this.result});
  

/// `set`, `invoke`, `wait`, `expect` or `sleep`.
@override final  String op;
/// The node the step is about (empty for `sleep`).
@override final  String key;
/// Its number in the plan, from 1.
@override@JsonKey() final  int n;
@override final  String? action;
/// `set`: `{value}`; `invoke`: its arguments; `expect`: the test
/// (`equals`, `min`/`max`, `changes`).
@override@JsonKey() final  IMap<String, Object?> args;
/// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
@override final  double? seconds;
/// `read`, `write` or `config`.
@override@JsonKey() final  String level;
/// The step needs a human token.
@override@JsonKey() final  bool approval;
/// `now` (checked against the live tree) or `at_run`.
@override@JsonKey() final  String check;
@override final  String? warn;
/// The steps (by number) this one needs.
@override@JsonKey() final  IList<int> after;
@override final  String? reason;
@override final  StepResult? result;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanStepCopyWith<_PlanStep> get copyWith => __$PlanStepCopyWithImpl<_PlanStep>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanStep&&(identical(other.op, op) || other.op == op)&&(identical(other.key, key) || other.key == key)&&(identical(other.n, n) || other.n == n)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args)&&(identical(other.seconds, seconds) || other.seconds == seconds)&&(identical(other.level, level) || other.level == level)&&(identical(other.approval, approval) || other.approval == approval)&&(identical(other.check, check) || other.check == check)&&(identical(other.warn, warn) || other.warn == warn)&&const DeepCollectionEquality().equals(other.after, after)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,op,key,n,action,args,seconds,level,approval,check,warn,const DeepCollectionEquality().hash(after),reason,result);
}

@override
String toString() {
    return 'PlanStep(op: $op, key: $key, n: $n, action: $action, args: $args, seconds: $seconds, level: $level, approval: $approval, check: $check, warn: $warn, after: $after, reason: $reason, result: $result)';
}


}

/// @nodoc
abstract mixin class _$PlanStepCopyWith<$Res> implements $PlanStepCopyWith<$Res> {
  factory _$PlanStepCopyWith(_PlanStep value, $Res Function(_PlanStep) _then) = __$PlanStepCopyWithImpl;
@override @useResult
$Res call({
 String op, String key, int n, String? action, IMap<String, Object?> args, double? seconds, String level, bool approval, String check, String? warn, IList<int> after, String? reason, StepResult? result
});


@override $StepResultCopyWith<$Res>? get result;

}
/// @nodoc
class __$PlanStepCopyWithImpl<$Res>
    implements _$PlanStepCopyWith<$Res> {
  __$PlanStepCopyWithImpl(this._self, this._then);

  final _PlanStep _self;
  final $Res Function(_PlanStep) _then;

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? op = null,Object? key = null,Object? n = null,Object? action = freezed,Object? args = null,Object? seconds = freezed,Object? level = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? after = null,Object? reason = freezed,Object? result = freezed,}) {
  return _then(_PlanStep(
op: null == op ? _self.op : op // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as String,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as IList<int>,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as StepResult?,
  ));
}

/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepResultCopyWith<$Res>? get result {
    if (_self.result == null) {
    return null;
  }

  return $StepResultCopyWith<$Res>(_self.result!, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

// dart format on
