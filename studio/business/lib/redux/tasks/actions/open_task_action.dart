import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_task_record_action.dart';
import 'set_selected_task_action.dart';

/// Opens task [id] (picked in the list, or the task that replaced the one
/// on screen): it is selected at once, then its record is read, with that
/// read's own wait.
class OpenTaskAction extends Action {
  OpenTaskAction(this.id);

  final String id;

  @override
  Future<AppState?> reduce() async {
    dispatchSync(SetSelectedTaskAction(id));
    await dispatchAndWait(RetrieveTaskRecordAction(id));
    return null;
  }
}
