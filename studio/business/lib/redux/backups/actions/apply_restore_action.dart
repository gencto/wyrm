import 'package:async_redux/async_redux.dart';
import 'package:models/backup_stage.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/backups` ▸ `restore_apply {upload, sections, mode, passphrase,
/// accept, replace_keys}`. `add` works live and answers `{done, skipped,
/// restart: false}`; `replace` stages the sections, answers `{sections,
/// restart: true}` and the broker stops: the next start applies them, and
/// Studio reconnects by itself. An answer of another shape is refused:
/// the dialog stays where it is and says so.
class ApplyRestoreAction extends Action with NonReentrant, WaitingAction {
  ApplyRestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final upload = backups.upload;
    if (upload == null) {
      return null;
    }
    final mode = backups.mode;
    final key = '${site.root}/sys/backups';
    final answer = await invokeOne(
      deps.wyrm,
      key,
      'restore_apply',
      valueOf({
        'upload': upload,
        'sections': [
          for (final s in mode.sections)
            if (backups.chosen.contains(s)) s.wire,
        ],
        'mode': mode.wire,
        if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
        if (backups.acceptRights) 'accept': true,
        if (backups.replaceKeys) 'replace_keys': true,
      }),
    );
    final applied = restoreAnswerOf(
      answer,
    ).orRefuse(key: key, call: 'restore_apply');
    return state.copyWith.backups(
      stage: applied.restart ? BackupStage.restarting : BackupStage.restored,
      staged: applied.sections,
      result: applied.restart
          ? null
          : [...applied.done, ...applied.skipped].join('\n'),
    );
  }
}
