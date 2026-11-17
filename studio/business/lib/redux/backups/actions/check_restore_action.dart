import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_section.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/backups` ▸ `restore_check {upload, passphrase}`: what the file is
/// and how it fits this broker. Every section of the file is then ticked
/// but `history` (large, and rarely what a restore is for) and `keys`
/// (which change the site's identity: the user ticks them on purpose). An
/// answer this client cannot read is refused: no check is shown, so
/// nothing can be restored on it.
class CheckRestoreAction extends Action with NonReentrant, WaitingAction {
  CheckRestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final upload = backups.upload;
    if (upload == null) {
      return null;
    }
    final key = '${site.root}/sys/backups';
    final answer = await askOne(
      deps.wyrm,
      key,
      'restore_check',
      valueOf({
        'upload': upload,
        if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
      }),
    );
    final check = restoreCheckOf(
      answer,
    ).orRefuse(key: key, call: 'restore_check');
    return state.copyWith.backups(
      check: check,
      chosen: check.sections.keys
          .where(
            (s) =>
                s != BackupSection.history &&
                s != BackupSection.keys &&
                s != BackupSection.config,
          )
          .toISet(),
    );
  }
}
