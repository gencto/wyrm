import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_audit_action.dart';

/// The audit marks of the Assistant drawer's mini timeline (spec
/// `assistant.md` §5): the records of `sys/audit` ▸ `tail` on the point
/// [key] or below it, into `assistant.timelineAudit`. Kept apart from
/// Explorer › Audit (`nodes.audit`), which reads the selected node. The
/// tail needs `config` on `sys/audit`: without it nothing is read and the
/// drawer says so. A refusal leaves no marks and a quiet line in Problems.
class RetrieveTimelineAuditAction extends Action with WaitingAction {
  RetrieveTimelineAuditAction(this.key, {this.n = 500}) : super(quiet: true);

  final String key;
  final int n;

  @override
  Future<AppState?> reduce() async {
    final root = key.split('/').take(2).join('/');
    if (!site.can('config', '$root/sys/audit')) {
      return state.copyWith.assistant(
        timelineKey: key,
        timelineAudit: const IListConst([]),
      );
    }
    final out = await RetrieveAuditAction.read(deps.wyrm, key, n: n);
    // a read for a point no longer selected is dropped
    if (nodes.point != key) {
      return null;
    }
    return state.copyWith.assistant(
      timelineKey: key,
      timelineAudit: out.lock,
    );
  }
}
