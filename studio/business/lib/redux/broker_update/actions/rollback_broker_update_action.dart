import 'package:async_redux/async_redux.dart';
import 'package:models/error_kind.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys` ▸ `rollback_update` (config, ADR 0048 §2.7): after a confirmed
/// update, until `keep_days`, the broker goes back to the version before
/// it and restores the pre-update backup of its control plane. Changes made
/// after the update are lost; the dialog's confirm says so.
class RollbackBrokerUpdateAction extends Action
    with NonReentrant, WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    try {
      await invokeOne(deps.wyrm, '$root/sys', 'rollback_update');
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
