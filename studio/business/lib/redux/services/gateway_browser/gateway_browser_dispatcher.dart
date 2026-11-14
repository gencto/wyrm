import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../../wyrm/discovery.dart';
import '../../app_state.dart';
import '../../discovery/actions/check_found_gateway_action.dart';
import 'gateway_browser.dart';

/// Each service the browse finds becomes a row to check.
class GatewayBrowserDispatcher implements GatewayBrowserServiceListener {
  GatewayBrowserDispatcher({required this._store});

  final Store<AppState> _store;

  @override
  void onFound(Announcement found, int scan) {
    unawaited(_store.dispatchAndWait(CheckFoundGatewayAction(found, scan)));
  }
}
