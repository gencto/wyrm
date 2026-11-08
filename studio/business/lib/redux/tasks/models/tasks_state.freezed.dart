// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tasks_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TasksState {

 IMap<String, AgentTask> get table; IList<String> get view; String? get selectedTask;
/// Create a copy of TasksState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TasksStateCopyWith<TasksState> get copyWith => _$TasksStateCopyWithImpl<TasksState>(this as TasksState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TasksState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedTask, selectedTask) || other.selectedTask == selectedTask));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedTask);

@override
String toString() {
  return 'TasksState(table: $table, view: $view, selectedTask: $selectedTask)';
}


}

/// @nodoc
abstract mixin class $TasksStateCopyWith<$Res>  {
  factory $TasksStateCopyWith(TasksState value, $Res Function(TasksState) _then) = _$TasksStateCopyWithImpl;
@useResult
$Res call({
 IMap<String, AgentTask> table, IList<String> view, String? selectedTask
});




}
/// @nodoc
class _$TasksStateCopyWithImpl<$Res>
    implements $TasksStateCopyWith<$Res> {
  _$TasksStateCopyWithImpl(this._self, this._then);

  final TasksState _self;
  final $Res Function(TasksState) _then;

/// Create a copy of TasksState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? table = null,Object? view = null,Object? selectedTask = freezed,}) {
  return _then(_self.copyWith(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, AgentTask>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedTask: freezed == selectedTask ? _self.selectedTask : selectedTask // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



/// @nodoc


class _TasksState implements TasksState {
  const _TasksState({this.table = const IMapConst({}), this.view = const IListConst([]), this.selectedTask});
  

@override@JsonKey() final  IMap<String, AgentTask> table;
@override@JsonKey() final  IList<String> view;
@override final  String? selectedTask;

/// Create a copy of TasksState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TasksStateCopyWith<_TasksState> get copyWith => __$TasksStateCopyWithImpl<_TasksState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TasksState&&(identical(other.table, table) || other.table == table)&&const DeepCollectionEquality().equals(other.view, view)&&(identical(other.selectedTask, selectedTask) || other.selectedTask == selectedTask));
}


@override
int get hashCode => Object.hash(runtimeType,table,const DeepCollectionEquality().hash(view),selectedTask);

@override
String toString() {
  return 'TasksState(table: $table, view: $view, selectedTask: $selectedTask)';
}


}

/// @nodoc
abstract mixin class _$TasksStateCopyWith<$Res> implements $TasksStateCopyWith<$Res> {
  factory _$TasksStateCopyWith(_TasksState value, $Res Function(_TasksState) _then) = __$TasksStateCopyWithImpl;
@override @useResult
$Res call({
 IMap<String, AgentTask> table, IList<String> view, String? selectedTask
});




}
/// @nodoc
class __$TasksStateCopyWithImpl<$Res>
    implements _$TasksStateCopyWith<$Res> {
  __$TasksStateCopyWithImpl(this._self, this._then);

  final _TasksState _self;
  final $Res Function(_TasksState) _then;

/// Create a copy of TasksState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? table = null,Object? view = null,Object? selectedTask = freezed,}) {
  return _then(_TasksState(
table: null == table ? _self.table : table // ignore: cast_nullable_to_non_nullable
as IMap<String, AgentTask>,view: null == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as IList<String>,selectedTask: freezed == selectedTask ? _self.selectedTask : selectedTask // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
