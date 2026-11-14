import 'package:async_redux/async_redux.dart';
import 'package:models/error_kind.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys` ▸ `update {version, confirm_site}` (config, ADR 0048 §2.4): the
/// broker checks the release, backs up its control plane, stages the new
/// binary and stops; the service manager starts the new one. The gateway
/// is lost on purpose: a call that ends because the broker stopped is the
/// expected end, and the dialog then follows `sys/update_state` once the
/// socket is back.
///
/// `confirm_site` is the site name as the user typed it: the broker
/// refuses the update unless it equals its own.
class UpdateBrokerAction extends Action with NonReentrant, WaitingAction {
  UpdateBrokerAction(this.version);

  final String version;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    try {
      await invokeOne(
        deps.wyrm,
        '$root/sys',
        'update',
        valueOf({'version': version, 'confirm_site': brokerUpdate.confirm}),
      );
    } on StudioException catch (e) {
      // The broker stops to start the other version: a call that ends
      // because the gateway went away is the expected end, not a
      // refusal. Anything else leaves as an error.
      if (e.error.kind != ErrorKind.reach) {
        rethrow;
      }
    }
    return state.copyWith.brokerUpdate(stage: 'follow');
  }
}
