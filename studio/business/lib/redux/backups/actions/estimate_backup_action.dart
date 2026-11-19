import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'create_backup_action.dart';

/// `sys/backups` ▸ `estimate {sections, links, history_days}` →
/// `{sections: {name: bytes}, total}`: the size of every section of the
/// broker backup as it is chosen now (before compression). Every section is
/// asked for, so an unticked row shows its size too. A link backup has no
/// estimate. The answer is dropped when the dialog it was asked for is no
/// longer the one open; one this client cannot read is refused (a toast
/// and a line in Problems say so, the field is in the log) and no size is
/// shown.
class EstimateBackupAction extends Action with WaitingAction {
  EstimateBackupAction() : super(quiet: true);

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || backups.link != null || backups.sections.isEmpty) {
      return null;
    }
    final opening = backups.opening;
    final answer = await askOne(
      deps.wyrm,
      '$root/sys/backups',
      'estimate',
      valueOf(
        backupArgs(
          sections: backups.sections,
          chosen: backups.sections.toSet(),
          allLinks: links.view,
          offLinks: backups.offLinks,
          historyDays: backups.historyDays,
        ),
      ),
    );
    // The dialog it was read for was closed, or another opened: dropped.
    if (backups.opening != opening || backups.stage == null) {
      return null;
    }
    return state.copyWith.backups(
      estimate: backupEstimateOf(
        answer,
      ).orRefuse(key: '$root/sys/backups', call: const .named('estimate')),
    );
  }
}
