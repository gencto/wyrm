import '../../../wyrm/log_in_page.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The standby gateway field was edited to [standby]; the main stays.
class SetStandbyGatewayAction extends Action {
  SetStandbyGatewayAction(this.standby);

  final String? standby;

  @override
  AppState reduce() => state.copyWith.login(
    gateway: GatewayField.of(login.gateway).withStandby(standby),
  );
}
