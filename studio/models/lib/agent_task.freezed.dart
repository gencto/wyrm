// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentTask {

 String get id; TaskState get state; String get owner; String get ask; IList<PlanStep> get plan; IList<String> get log; String? get error; int get tokens;
/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentTaskCopyWith<AgentTask> get copyWith => _$AgentTaskCopyWithImpl<AgentTask>(this as AgentTask, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.ask, ask) || other.ask == ask)&&const DeepCollectionEquality().equals(other.plan, plan)&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.error, error) || other.error == error)&&(identical(other.tokens, tokens) || other.tokens == tokens));
}


@override
int get hashCode => Object.hash(runtimeType,id,state,owner,ask,const DeepCollectionEquality().hash(plan),const DeepCollectionEquality().hash(log),error,tokens);

@override
String toString() {
  return 'AgentTask(id: $id, state: $state, owner: $owner, ask: $ask, plan: $plan, log: $log, error: $error, tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class $AgentTaskCopyWith<$Res>  {
  factory $AgentTaskCopyWith(AgentTask value, $Res Function(AgentTask) _then) = _$AgentTaskCopyWithImpl;
@useResult
$Res call({
 String id, TaskState state, String owner, String ask, IList<PlanStep> plan, IList<String> log, String? error, int tokens
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? log = null,Object? error = freezed,Object? tokens = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as IList<PlanStep>,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}



/// @nodoc


class _AgentTask implements AgentTask {
  const _AgentTask({required this.id, this.state = TaskState.planning, this.owner = '', this.ask = '', this.plan = const IListConst([]), this.log = const IListConst([]), this.error, this.tokens = 0});
  

@override final  String id;
@override@JsonKey() final  TaskState state;
@override@JsonKey() final  String owner;
@override@JsonKey() final  String ask;
@override@JsonKey() final  IList<PlanStep> plan;
@override@JsonKey() final  IList<String> log;
@override final  String? error;
@override@JsonKey() final  int tokens;

/// Create a copy of AgentTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentTaskCopyWith<_AgentTask> get copyWith => __$AgentTaskCopyWithImpl<_AgentTask>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentTask&&(identical(other.id, id) || other.id == id)&&(identical(other.state, state) || other.state == state)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.ask, ask) || other.ask == ask)&&const DeepCollectionEquality().equals(other.plan, plan)&&const DeepCollectionEquality().equals(other.log, log)&&(identical(other.error, error) || other.error == error)&&(identical(other.tokens, tokens) || other.tokens == tokens));
}


@override
int get hashCode => Object.hash(runtimeType,id,state,owner,ask,const DeepCollectionEquality().hash(plan),const DeepCollectionEquality().hash(log),error,tokens);

@override
String toString() {
  return 'AgentTask(id: $id, state: $state, owner: $owner, ask: $ask, plan: $plan, log: $log, error: $error, tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class _$AgentTaskCopyWith<$Res> implements $AgentTaskCopyWith<$Res> {
  factory _$AgentTaskCopyWith(_AgentTask value, $Res Function(_AgentTask) _then) = __$AgentTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, TaskState state, String owner, String ask, IList<PlanStep> plan, IList<String> log, String? error, int tokens
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? state = null,Object? owner = null,Object? ask = null,Object? plan = null,Object? log = null,Object? error = freezed,Object? tokens = null,}) {
  return _then(_AgentTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TaskState,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,ask: null == ask ? _self.ask : ask // ignore: cast_nullable_to_non_nullable
as String,plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as IList<PlanStep>,log: null == log ? _self.log : log // ignore: cast_nullable_to_non_nullable
as IList<String>,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
