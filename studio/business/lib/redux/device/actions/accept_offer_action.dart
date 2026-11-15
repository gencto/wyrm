import 'package:models/unlock_stage.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'decline_offer_action.dart';
import 'enable_device_action.dart';

/// `Use <name>` on the offer (board `UnlockOffer`): the key is made and
/// registered; on a computer with no biometric (`Open Studio`) the offer
/// is only closed. Whatever the registration answers, the offer is over:
/// a gateway that wants a fresh password first (`password_required`)
/// leaves the key for Account › Security, as a refusal does. The step to
/// Studio is the app's.
class AcceptOfferAction extends Action {
  @override
  Future<AppState?> reduce() async {
    if (device.available) {
      await dispatchAndWait(EnableDeviceAction());
    } else {
      await dispatchAndWait(DeclineOfferAction());
    }
    // The state now: a registration that asked for the password left it.
    return device.stage == UnlockStage.offer
        ? state.copyWith.device(stage: UnlockStage.none)
        : null;
  }
}
