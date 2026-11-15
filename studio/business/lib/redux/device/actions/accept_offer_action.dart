import '../../app_state.dart';
import '../../common/action.dart';
import 'decline_offer_action.dart';
import 'enable_device_action.dart';

/// `Use <name>` on the offer (board `UnlockOffer`): the key is made and
/// registered; on a computer with no biometric (`Open Studio`) the offer
/// is only closed. The step to Studio is the app's.
class AcceptOfferAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (device.available) {
      await dispatchAndWait(EnableDeviceAction());
    } else {
      await dispatchAndWait(DeclineOfferAction());
    }
    return null;
  }
}
