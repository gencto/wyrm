import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
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
    await invokeOne(deps.wyrm, '$root/sys', 'rollback_update');
    return state.copyWith.brokerUpdate(stage: 'follow');
  }
}
