import 'package:async_redux/async_redux.dart';

import '../../../wyrm/discovery.dart';
import '../../app_state.dart';
import '../../discovery/actions/check_found_gateway_action.dart';
import 'gateway_browser.dart';

/// Each service the browse finds becomes a row to check.
class GatewayBrowserDispatcher implements GatewayBrowserServiceListener {
  GatewayBrowserDispatcher({required this._store});

  final Store<AppState> _store;

  /// A stream listener does not wait (studio-rules §1): it dispatches and
  /// returns; the check drops an answer of an older search itself.
  @override
  void onFound(Announcement found, int scan) =>
      _store.dispatch(CheckFoundGatewayAction(found, scan));
}
