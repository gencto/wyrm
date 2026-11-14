import '../../app_state.dart';
import '../../common/action.dart';

class SetAcceptNewAction extends Action {
  SetAcceptNewAction(this.acceptNew);

  final bool acceptNew;

  @override
  AppState reduce() => state.copyWith.updates(acceptNew: acceptNew);
}
