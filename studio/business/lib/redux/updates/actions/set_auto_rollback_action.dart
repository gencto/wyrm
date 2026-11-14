import '../../app_state.dart';
import '../../common/action.dart';

class SetAutoRollbackAction extends Action {
  SetAutoRollbackAction(this.autoRollback);

  final bool autoRollback;

  @override
  AppState reduce() => state.copyWith.updates(autoRollback: autoRollback);
}
