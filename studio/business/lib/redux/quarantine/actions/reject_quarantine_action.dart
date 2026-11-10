import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_quarantine_action.dart';

/// `sys/quarantine/<node>` ▸ `reject` (config): this CN is refused from now
/// on.
class RejectQuarantineAction extends Action with WaitingAction {
  RejectQuarantineAction(this.node);

  @override
  Action again() => RejectQuarantineAction(node);

  @override
  Action reload() => RetrieveQuarantineAction();

  final String node;

  @override
  Future<AppState> reduce() async {
    await invokeAll(deps.wyrm, '${site.root}/sys/quarantine/$node', 'reject');
    return state.copyWith.quarantine(
      table: quarantine.table.remove(node),
      view: quarantine.view.remove(node),
      selectedEntry: null,
    );
  }
}
