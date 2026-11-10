import 'package:async_redux/async_redux.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_quarantine_action.dart';

/// `sys/quarantine/<node>` ▸ `approve` (config) with the arguments of its
/// form: the connection becomes an external link (or a downstream broker)
/// with its own branch. The router rebuilds for about a second.
class ApproveQuarantineAction extends Action with NonReentrant, WaitingAction {
  ApproveQuarantineAction(this.node, this.args);

  @override
  Action again() => ApproveQuarantineAction(node, args);

  @override
  Action reload() => RetrieveQuarantineAction();

  final String node;
  final Map<String, Object?> args;

  @override
  Future<AppState> reduce() async {
    await invokeAll(
      deps.wyrm,
      '${site.root}/sys/quarantine/$node',
      'approve',
      Value.from({
        for (final MapEntry(:key, :value) in args.entries)
          if (value != null && value != '') key: value,
      }),
    );
    return state.copyWith.quarantine(
      table: quarantine.table.remove(node),
      view: quarantine.view.remove(node),
      selectedEntry: null,
    );
  }
}
