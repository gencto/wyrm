import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_link_history_action.dart';

/// `sys/links/<id>` ▸ `rollback {rev}` (config): the parameters of [rev]
/// become a new revision and the link restarts with them.
class RollbackLinkParamsAction extends Action with WaitingAction {
  RollbackLinkParamsAction(this.id, this.rev);

  final String id;
  final int rev;

  @override
  Future<AppState?> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/links/$id',
      'rollback',
      Value.from({'rev': rev}),
    );
    return null;
  }

  @override
  void after() {
    super.after();
    unawaited(dispatchAndWait(RetrieveLinkHistoryAction(id)));
  }
}
