import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedTaskAction extends Action {
  SetSelectedTaskAction(this.selectedTask);

  final String? selectedTask;

  @override
  AppState reduce() => state.copyWith.tasks(selectedTask: selectedTask);
}
