import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Ends the session (docs/studio.md §5.1): closes every subscription and the
/// client, and empties every slice the broker filled. Theme, language and the
/// last gateway and user stay; the auth guard sees the token go and shows the
/// log-in page.
class LogOutAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await deps.detach();
    return loggedOut(state);
  }
}

/// [s] after a log out: what the broker filled is gone. Theme, language,
/// the log-in form without its password and the device unlock (what this
/// computer offers, the key of the form's user and why it last stopped)
/// stay, so the log-in page shows the same unlock again (ADR 0050).
AppState loggedOut(AppState s) => AppState.initial().copyWith(
  theme: s.theme,
  language: s.language,
  connectivity: s.connectivity,
  wait: s.wait,
  login: s.login.copyWith(password: null),
  device: s.device.copyWith(
    locked: false,
    lockError: null,
    stepUp: null,
    needPassword: false,
    securityError: null,
    devices: const IListConst([]),
    userDevices: const IMapConst({}),
  ),
);
