import '../../app_state.dart';
import '../../common/action.dart';
import '../../device/actions/load_device_action.dart';
import 'probe_gateway_action.dart';

/// The log-in page opens (docs/design/specs/login.md §6,
/// unlock-discover.md §2): the gateway in the field is probed and the
/// device unlock of its user is read, side by side. Each has its own
/// state; this one changes none.
class OpenLogInAction extends Action {
  @override
  Future<AppState?> reduce() async {
    await Future.wait([
      dispatchAndWait(ProbeGatewayAction()),
      dispatchAndWait(LoadDeviceAction()),
    ]);
    return null;
  }
}
