import 'package:models/unlock_stage.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// `Use the password` under the round button: the password for the same
/// user, the key kept (board `Unlock` → its fallback form, without a
/// notice).
class UsePasswordAction extends Action {
  @override
  AppState reduce() => state.copyWith.device(
    stage: UnlockStage.fallback,
    reason: null,
    autoPrompted: true,
  );
}
