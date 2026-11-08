import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/agent_task.dart';

part 'tasks_state.freezed.dart';

@freezed
abstract class TasksState with _$TasksState {
  const factory TasksState({
    @Default(IMapConst({})) IMap<String, AgentTask> table,
    @Default(IListConst([])) IList<String> view,
    String? selectedTask,
  }) = _TasksState;
}
