import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/backup_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/backups` ▸ `restore_check {upload, passphrase}`: what the file is
/// and how it fits this broker. Every section of the file is then ticked
/// but `history` (large, and rarely what a restore is for) and `keys`
/// (which change the site's identity: the user ticks them on purpose).
class CheckRestoreAction extends Action with NonReentrant, WaitingAction {
  CheckRestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final upload = backups.upload;
    if (upload == null) {
      return null;
    }
    final answer = await askOne(
      deps.wyrm,
      '${site.root}/sys/backups',
      'restore_check',
      valueOf({
        'upload': upload,
        if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
      }),
    );
    final check = restoreCheckOf(answer);
    return state.copyWith.backups(
      check: check,
      chosen: check.sections.keys
          .where((s) => s != 'history' && s != 'keys' && s != 'config')
          .toISet(),
    );
  }
}
