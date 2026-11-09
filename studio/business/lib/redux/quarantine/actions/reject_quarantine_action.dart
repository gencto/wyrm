import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/quarantine/<node>` ▸ `reject` (config): this CN is refused from now
/// on.
class RejectQuarantineAction extends Action with WaitingAction {
  RejectQuarantineAction(this.node);

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
