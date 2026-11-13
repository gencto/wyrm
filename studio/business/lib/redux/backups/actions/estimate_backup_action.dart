import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'create_backup_action.dart';

/// `sys/backups` ▸ `estimate {sections, links, history_days}` →
/// `{sections: {name: bytes}, total}`: the size of every section of the
/// broker backup as it is chosen now (before compression). Every section is
/// asked for, so an unticked row shows its size too. A link backup has no
/// estimate.
class EstimateBackupAction extends Action with WaitingAction {
  EstimateBackupAction() : super(quiet: true);

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null || backups.link != null || backups.sections.isEmpty) {
      return null;
    }
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
    return state.copyWith.backups(
      estimate: {
        if (answer['sections'] case VMap(:final v))
          for (final e in v.entries) e.key: integer(e.value) ?? 0,
      }.lock,
    );
  }
}
