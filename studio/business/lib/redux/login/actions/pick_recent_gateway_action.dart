import '../../app_state.dart';
import '../../common/action.dart';
import '../../device/actions/load_device_action.dart';
import 'probe_gateway_action.dart';
import 'set_gateway_action.dart';

/// A recent chip was tapped (docs/design/specs/login.md §6): the field
/// gets the chip's [gateway] at once, then the gateway is probed and the
/// device unlock of the user is read for it, side by side.
class PickRecentGatewayAction extends Action {
  PickRecentGatewayAction(this.gateway);

  /// The field's text the chip puts back.
  final String gateway;

  @override
  Future<AppState?> reduce() async {
    // Shown at once: the field and the chip that is now current.
    dispatchSync(SetGatewayAction(gateway));
    await Future.wait([
      dispatchAndWait(ProbeGatewayAction(gateway)),
      dispatchAndWait(LoadDeviceAction()),
    ]);
    return null;
  }
}
