import '../../../wyrm/log_in_page.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_gateway_action.dart';
import 'sign_in_action.dart';

/// *Use the standby* in the unreachable alert (ADR 0036): the standby
/// becomes the first gateway of the field, then the log-in runs again.
class UseStandbyAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final field = GatewayField.of(login.gateway);
    if (field.standby == null) {
      return null;
    }
    dispatchSync(SetGatewayAction(field.swapped));
    await dispatchAndWait(SignInAction());
    return null;
  }
}
