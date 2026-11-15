import '../../../wyrm/log_in_page.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// The main gateway field was edited to [main]; the standby stays.
class SetMainGatewayAction extends Action {
  SetMainGatewayAction(this.main);

  final String? main;

  @override
  AppState reduce() => state.copyWith.login(
    gateway: GatewayField.of(login.gateway).withMain(main),
  );
}
