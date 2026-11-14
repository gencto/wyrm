import 'package:models/unlock_stage.dart';

import '../../../wyrm/device_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Not now` and `Don't ask on this computer` on the offer (board
/// `UnlockOffer`): the offer was shown once and is not shown again for
/// this gateway and user; [dontAsk] keeps that choice even when a key is
/// turned off later. Account › Security can still turn the unlock on.
class DeclineOfferAction extends Action {
  DeclineOfferAction({this.dontAsk = false});

  final bool dontAsk;

  @override
  Future<AppState?> reduce() async {
    final account = accountOf(login.gateway, login.user);
    if (account != null) {
      final records = deps.deviceRecords;
      final r = await records.read(account.origin, account.user);
      await records.write(
        account.origin,
        account.user,
        r.copyWith(offered: true, dontAsk: dontAsk || r.dontAsk),
      );
    }
    return state.copyWith.device(
      stage: UnlockStage.none,
      offered: true,
      dontAsk: dontAsk || state.device.dontAsk,
    );
  }
}
