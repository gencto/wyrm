import '../../app_state.dart';
import '../../common/action.dart';

class SetReEnableAction extends Action {
  SetReEnableAction(this.reEnable);

  final bool reEnable;

  @override
  AppState reduce() => state.copyWith.device(reEnable: reEnable);
}
