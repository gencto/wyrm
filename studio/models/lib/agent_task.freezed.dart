// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentTask {

 String get id; TaskState get state; String get owner; String get ask; IList<PlanStep> get plan; IList<String> get log; String? get error; int get tokens;/// The hash of [plan] as it was read: what an approval is bound to.
 String? get planHash;/// The step the run is at (its number; 0 before a run), from the
/// public `~val.step` and the record.
 int get step;/// The task this one follows.
 String? get parent;/// The record (`~state`) was read; before that only the state is known.
 bool get recorded;
/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentTaskCopyWith<AgentTask> get copyWith => _$AgentTaskCopyWithImpl<AgentTask>(this as AgentTask, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentTask;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentTask&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.ask, _this.ask) || other.ask == _this.ask)&&const DeepCollectionEquality().equals(other.plan, _this.plan)&&const DeepCollectionEquality().equals(other.log, _this.log)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.tokens, _this.tokens) || other.tokens == _this.tokens)&&(identical(other.planHash, _this.planHash) || other.planHash == _this.planHash)&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&(identical(other.recorded, _this.recorded) || other.recorded == _this.recorded));
}


@override
int get hashCode {
  final _this = this as AgentTask;
  return Object.hash(runtimeType,_this.id,_this.state,_this.owner,_this.ask,const DeepCollectionEquality().hash(_this.plan),const DeepCollectionEquality().hash(_this.log),_this.error,_this.tokens,_this.planHash,_this.step,_this.parent,_this.recorded);
}

@override
String toString() {
  final _this = this as AgentTask;
  return 'AgentTask(id: ${_this.id}, state: ${_this.state}, owner: ${_this.owner}, ask: ${_this.ask}, plan: ${_this.plan}, log: ${_this.log}, error: ${_this.error}, tokens: ${_this.tokens}, planHash: ${_this.planHash}, step: ${_this.step}, parent: ${_this.parent}, recorded: ${_this.recorded})';
}


}

/// @nodoc
abstract mixin class $AgentTaskCopyWith<$Res>  {
  factory $AgentTaskCopyWith(AgentTask value, $Res Function(AgentTask) _then) = _$AgentTaskCopyWithImpl;
@useResult
$Res call({
 String id, TaskState state, String owner, String ask, IList<PlanStep> plan, IList<String> log, String? error, int tokens, String? planHash, int step, String? parent, bool recorded
});




}
/// @nodoc
class _$AgentTaskCopyWithImpl<$Res>
    implements $AgentTaskCopyWith<$Res> {
  _$AgentTaskCopyWithImpl(this._self, this._then);

  final AgentTask _self;
  final $Res Function(AgentTask) _then;

/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? log = null,Object? error = freezed,Object? tokens = null,Object? planHash = freezed,Object? step = null,Object? parent = freezed,Object? recorded = null,}) {
  return _then(AgentTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as IList<PlanStep>,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,planHash: freezed == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as String?,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,recorded: null == recorded ? _self.recorded : recorded // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _AgentTask implements AgentTask {
  const _AgentTask({required this.id, this.state = TaskState.planning, this.owner = '', this.ask = '', this.plan = const IListConst([]), this.log = const IListConst([]), this.error, this.tokens = 0, this.planHash, this.step = 0, this.parent, this.recorded = false});
  

@override final  String id;
@override@JsonKey() final  TaskState state;
@override@JsonKey() final  String owner;
@override@JsonKey() final  String ask;
@override@JsonKey() final  IList<PlanStep> plan;
@override@JsonKey() final  IList<String> log;
@override final  String? error;
@override@JsonKey() final  int tokens;
/// The hash of [plan] as it was read: what an approval is bound to.
@override final  String? planHash;
/// The step the run is at (its number; 0 before a run), from the
/// public `~val.step` and the record.
@override@JsonKey() final  int step;
/// The task this one follows.
@override final  String? parent;
/// The record (`~state`) was read; before that only the state is known.
@override@JsonKey() final  bool recorded;

/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentTaskCopyWith<_AgentTask> get copyWith => __$AgentTaskCopyWithImpl<_AgentTask>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.ask, ask) || other.ask == ask)&&const DeepCollectionEquality().equals(other.plan, plan)&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.error, error) || other.error == error)&&(identical(other.tokens, tokens) || other.tokens == tokens)&&(identical(other.planHash, planHash) || other.planHash == planHash)&&(identical(other.step, step) || other.step == step)&&(identical(other.parent, parent) || other.parent == parent)&&(identical(other.recorded, recorded) || other.recorded == recorded));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,state,owner,ask,const DeepCollectionEquality().hash(plan),const DeepCollectionEquality().hash(log),error,tokens,planHash,step,parent,recorded);
}

@override
String toString() {
    return 'AgentTask(id: $id, state: $state, owner: $owner, ask: $ask, plan: $plan, log: $log, error: $error, tokens: $tokens, planHash: $planHash, step: $step, parent: $parent, recorded: $recorded)';
}


}

/// @nodoc
abstract mixin class _$AgentTaskCopyWith<$Res> implements $AgentTaskCopyWith<$Res> {
  factory _$AgentTaskCopyWith(_AgentTask value, $Res Function(_AgentTask) _then) = __$AgentTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, TaskState state, String owner, String ask, IList<PlanStep> plan, IList<String> log, String? error, int tokens, String? planHash, int step, String? parent, bool recorded
});




}
/// @nodoc
class __$AgentTaskCopyWithImpl<$Res>
    implements _$AgentTaskCopyWith<$Res> {
  __$AgentTaskCopyWithImpl(this._self, this._then);

  final _AgentTask _self;
  final $Res Function(_AgentTask) _then;

/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? log = null,Object? error = freezed,Object? tokens = null,Object? planHash = freezed,Object? step = null,Object? parent = freezed,Object? recorded = null,}) {
  return _then(_AgentTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as IList<PlanStep>,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,planHash: freezed == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as String?,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as int,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as String?,recorded: null == recorded ? _self.recorded : recorded // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
