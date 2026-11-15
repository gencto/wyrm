import '../../../wyrm/gateway_label.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../device/actions/offer_device_action.dart';
import 'log_in_action.dart';
import 'set_gateway_action.dart';

/// *Log in* on the page (docs/design/specs/login.md §5, unlock-discover.md
/// §2): the password log-in, then what comes before Welcome — the offer of
/// a device key, or a key made again. It ends with `device.stage` =
/// `offer` when the page must wait for the person; the step to Studio is
/// the app's (`EnterStudioAction`).
class SignInAction extends Action {
  @override
  Future<AppState?> reduce() async {
    // The demo gateway shown in the field is only a hint until it is
    // written: the log-in sends it, and the field keeps it.
    if (login.gateway == null) {
      dispatchSync(SetGatewayAction(defaultGateway), notify: false);
    }
    final status = await dispatchAndWait(LogInAction());
    if (!status.isCompletedOk) {
      return null;
    }
    await dispatchAndWait(OfferDeviceAction());
    return null;
  }
}
