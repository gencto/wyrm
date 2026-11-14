import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';

/// *Find on this network* again while the panel is open: the panel closes,
/// the browse stops and the answers still on their way are dropped.
class CloseDiscoveryAction extends Action {
  @override
  AppState reduce() {
    unawaited(deps.gatewayBrowser.stop());
    return state.copyWith.discovery(
      open: false,
      scanning: false,
      scan: discovery.scan + 1,
      trustPending: null,
      trustRefused: null,
    );
  }
}
