import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../quarantine/actions/approve_quarantine_action.dart';
import 'retrieve_peers_action.dart';

/// Authorize a broker that waits in quarantine (its entry's `approve` with
/// the key it was reviewed with and the sites it relays, ADR 0015, 0031).
class AuthorizeBrokerAction extends Action with NonReentrant, WaitingAction {
  AuthorizeBrokerAction(this.node, this.args);

  final String node;
  final Map<String, Object?> args;

  @override
  Future<AppState?> reduce() async {
    await dispatchAndWait(ApproveQuarantineAction(node, args));
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrievePeersAction()));
  }
}
