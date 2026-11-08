import '../../app_state.dart';
import '../../common/action.dart';

class SetBrokerAction extends Action {
  SetBrokerAction(this.broker);

  final String? broker;

  @override
  AppState reduce() => state.copyWith.linkInstall(broker: broker);
}
