import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/device_keys.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `Confirm with <name>` or, with [password], `Use the password` in the
/// step-up dialog: the device key signs the refused request's hash
/// (`POST /api/device/confirm`), or the password confirms the session
/// (`POST /api/confirm`). Then the dialog closes and the same request goes
/// again (the gate of `AppDependencies`). A cancelled prompt or a wrong
/// password keeps the dialog open with its line.
class ConfirmStepUpAction extends Action with NonReentrant, WaitingAction {
  ConfirmStepUpAction({required this.reason, this.password});

  /// The prompt's line.
  final String reason;
  final String? password;

  @override
  Future<AppState?> reduce() async {
    final pending = state.device.stepUp;
    final refusal = deps.stepUpRefusal;
    final session = deps.rawSession;
    if (pending == null || refusal == null || session == null) {
      return null;
    }
    dispatchSync(_Busy(busy: true));
    try {
      if (password case final pw?) {
        await session.confirmWithPassword(pw);
      } else {
        final d = state.device;
        final account = accountOf(login.gateway, login.user);
        if (d.keyId == null || d.deviceId == null || account == null) {
          return state.copyWith.device(
            stepUp: pending.copyWith(busy: false, passwordOnly: true),
          );
        }
        await session.confirmWithDevice(
          e: refusal,
          site: site.name ?? d.keySite ?? '',
          user: account.user,
          device: d.deviceId!,
          sign: signer(deps.deviceKey, d.keyId!, reason),
        );
      }
    } on SignStopped catch (e) {
      return state.copyWith.device(
        stepUp: pending.copyWith(busy: false, error: '$e'),
      );
    } on WyrmException catch (e) {
      return state.copyWith.device(
        stepUp: pending.copyWith(
          busy: false,
          error: e.code ?? e.message,
          // The key is not taken any more: the password still is.
          passwordOnly: pending.passwordOnly || password == null,
        ),
      );
    }
    deps.endStepUp(confirmed: true);
    return state.copyWith.device(stepUp: null);
  }
}

class _Busy extends Action {
  _Busy({required this.busy});

  final bool busy;

  @override
  AppState? reduce() {
    final s = state.device.stepUp;
    return s == null
        ? null
        : state.copyWith.device(stepUp: s.copyWith(busy: busy, error: null));
  }
}
