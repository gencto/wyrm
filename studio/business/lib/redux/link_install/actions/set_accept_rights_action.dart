import '../../app_state.dart';
import '../../common/action.dart';

class SetAcceptRightsAction extends Action {
  SetAcceptRightsAction(this.acceptRights);

  final bool acceptRights;

  @override
  AppState reduce() => state.copyWith.linkInstall(acceptRights: acceptRights);
}
