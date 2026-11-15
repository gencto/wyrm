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

/// What the step does.
 StepKind get kind;/// The node the step is about (empty for `sleep`).
 String get key;/// Its number in the plan, from 1.
 int get n; String? get action;/// `set`: `{value}`; `invoke`: its arguments; `expect`: the test
/// (`equals`, `min`/`max`, `changes`).
 IMap<String, Object?> get args;/// The names of [args] the action's `~meta` marks as secret (a
/// password editor): never shown, never written to a file.
 ISet<String> get secret;/// The schema of [args] is known (the `~meta` of the step's node was
/// read). When it is not (`check: at_run`, the node does not exist
/// yet; or the meta could not be read), any argument may be a secret:
/// all are masked until the person reveals them, and none is written
/// to a file.
 bool get argsKnown;/// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
 double? get seconds;/// The level the step needs.
 Perm get level;/// The step needs a human token.
 bool get approval;/// When it was checked against the tree.
 StepCheck get check;/// The link's own finding about the step (a checked conclusion).
 String? get warn;/// The model's words about the step (`model_warn`): never shown as a
/// check of the link.
 String? get modelWarn;/// The steps (by number) this one needs.
 IList<int> get after; String? get reason; StepResult? get result;
/// Create a copy of PlanStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanStepCopyWith<PlanStep> get copyWith => _$PlanStepCopyWithImpl<PlanStep>(this as PlanStep, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanStep&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.n, _this.n) || other.n == _this.n)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.args, _this.args) || other.args == _this.args)&&const DeepCollectionEquality().equals(other.secret, _this.secret)&&(identical(other.argsKnown, _this.argsKnown) || other.argsKnown == _this.argsKnown)&&(identical(other.seconds, _this.seconds) || other.seconds == _this.seconds)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.approval, _this.approval) || other.approval == _this.approval)&&(identical(other.check, _this.check) || other.check == _this.check)&&(identical(other.warn, _this.warn) || other.warn == _this.warn)&&(identical(other.modelWarn, _this.modelWarn) || other.modelWarn == _this.modelWarn)&&const DeepCollectionEquality().equals(other.after, _this.after)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.result, _this.result) || other.result == _this.result));
}


@override
int get hashCode {
  final _this = this as PlanStep;
  return Object.hash(runtimeType,_this.kind,_this.key,_this.n,_this.action,_this.args,const DeepCollectionEquality().hash(_this.secret),_this.argsKnown,_this.seconds,_this.level,_this.approval,_this.check,_this.warn,_this.modelWarn,const DeepCollectionEquality().hash(_this.after),_this.reason,_this.result);
}

@override
String toString() {
  final _this = this as PlanStep;
  return 'PlanStep(kind: ${_this.kind}, key: ${_this.key}, n: ${_this.n}, action: ${_this.action}, args: ${_this.args}, secret: ${_this.secret}, argsKnown: ${_this.argsKnown}, seconds: ${_this.seconds}, level: ${_this.level}, approval: ${_this.approval}, check: ${_this.check}, warn: ${_this.warn}, modelWarn: ${_this.modelWarn}, after: ${_this.after}, reason: ${_this.reason}, result: ${_this.result})';
}


}

/// @nodoc
abstract mixin class $PlanStepCopyWith<$Res>  {
  factory $PlanStepCopyWith(PlanStep value, $Res Function(PlanStep) _then) = _$PlanStepCopyWithImpl;
@useResult
$Res call({
 StepKind kind, String key, int n, String? action, IMap<String, Object?> args, ISet<String> secret, bool argsKnown, double? seconds, Perm level, bool approval, StepCheck check, String? warn, String? modelWarn, IList<int> after, String? reason, StepResult? result
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
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? key = null,Object? n = null,Object? action = freezed,Object? args = null,Object? secret = null,Object? argsKnown = null,Object? seconds = freezed,Object? level = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? modelWarn = freezed,Object? after = null,Object? reason = freezed,Object? result = freezed,}) {
  return _then(PlanStep(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as StepKind,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as ISet<String>,argsKnown: null == argsKnown ? _self.argsKnown : argsKnown // ignore: cast_nullable_to_non_nullable
as bool,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as StepCheck,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,modelWarn: freezed == modelWarn ? _self.modelWarn : modelWarn // ignore: cast_nullable_to_non_nullable
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
  const _PlanStep({required this.kind, required this.key, this.n = 0, this.action, this.args = const IMapConst({}), this.secret = const ISetConst({}), this.argsKnown = true, this.seconds, this.level = Perm.write, this.approval = false, this.check = StepCheck.now, this.warn, this.modelWarn, this.after = const IListConst([]), this.reason, this.result});
  

/// What the step does.
@override final  StepKind kind;
/// The node the step is about (empty for `sleep`).
@override final  String key;
/// Its number in the plan, from 1.
@override@JsonKey() final  int n;
@override final  String? action;
/// `set`: `{value}`; `invoke`: its arguments; `expect`: the test
/// (`equals`, `min`/`max`, `changes`).
@override@JsonKey() final  IMap<String, Object?> args;
/// The names of [args] the action's `~meta` marks as secret (a
/// password editor): never shown, never written to a file.
@override@JsonKey() final  ISet<String> secret;
/// The schema of [args] is known (the `~meta` of the step's node was
/// read). When it is not (`check: at_run`, the node does not exist
/// yet; or the meta could not be read), any argument may be a secret:
/// all are masked until the person reveals them, and none is written
/// to a file.
@override@JsonKey() final  bool argsKnown;
/// `wait`/`expect`: the timeout; `sleep`: its length. Seconds.
@override final  double? seconds;
/// The level the step needs.
@override@JsonKey() final  Perm level;
/// The step needs a human token.
@override@JsonKey() final  bool approval;
/// When it was checked against the tree.
@override@JsonKey() final  StepCheck check;
/// The link's own finding about the step (a checked conclusion).
@override final  String? warn;
/// The model's words about the step (`model_warn`): never shown as a
/// check of the link.
@override final  String? modelWarn;
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanStep&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.key, key) || other.key == key)&&(identical(other.n, n) || other.n == n)&&(identical(other.action, action) || other.action == action)&&(identical(other.args, args) || other.args == args)&&const DeepCollectionEquality().equals(other.secret, secret)&&(identical(other.argsKnown, argsKnown) || other.argsKnown == argsKnown)&&(identical(other.seconds, seconds) || other.seconds == seconds)&&(identical(other.level, level) || other.level == level)&&(identical(other.approval, approval) || other.approval == approval)&&(identical(other.check, check) || other.check == check)&&(identical(other.warn, warn) || other.warn == warn)&&(identical(other.modelWarn, modelWarn) || other.modelWarn == modelWarn)&&const DeepCollectionEquality().equals(other.after, after)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,key,n,action,args,const DeepCollectionEquality().hash(secret),argsKnown,seconds,level,approval,check,warn,modelWarn,const DeepCollectionEquality().hash(after),reason,result);
}

@override
String toString() {
    return 'PlanStep(kind: $kind, key: $key, n: $n, action: $action, args: $args, secret: $secret, argsKnown: $argsKnown, seconds: $seconds, level: $level, approval: $approval, check: $check, warn: $warn, modelWarn: $modelWarn, after: $after, reason: $reason, result: $result)';
}


}

/// @nodoc
abstract mixin class _$PlanStepCopyWith<$Res> implements $PlanStepCopyWith<$Res> {
  factory _$PlanStepCopyWith(_PlanStep value, $Res Function(_PlanStep) _then) = __$PlanStepCopyWithImpl;
@override @useResult
$Res call({
 StepKind kind, String key, int n, String? action, IMap<String, Object?> args, ISet<String> secret, bool argsKnown, double? seconds, Perm level, bool approval, StepCheck check, String? warn, String? modelWarn, IList<int> after, String? reason, StepResult? result
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
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? key = null,Object? n = null,Object? action = freezed,Object? args = null,Object? secret = null,Object? argsKnown = null,Object? seconds = freezed,Object? level = null,Object? approval = null,Object? check = null,Object? warn = freezed,Object? modelWarn = freezed,Object? after = null,Object? reason = freezed,Object? result = freezed,}) {
  return _then(_PlanStep(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as StepKind,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,action: freezed == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String?,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as IMap<String, Object?>,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as ISet<String>,argsKnown: null == argsKnown ? _self.argsKnown : argsKnown // ignore: cast_nullable_to_non_nullable
as bool,seconds: freezed == seconds ? _self.seconds : seconds // ignore: cast_nullable_to_non_nullable
as double?,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as Perm,approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as bool,check: null == check ? _self.check : check // ignore: cast_nullable_to_non_nullable
as StepCheck,warn: freezed == warn ? _self.warn : warn // ignore: cast_nullable_to_non_nullable
as String?,modelWarn: freezed == modelWarn ? _self.modelWarn : modelWarn // ignore: cast_nullable_to_non_nullable
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
