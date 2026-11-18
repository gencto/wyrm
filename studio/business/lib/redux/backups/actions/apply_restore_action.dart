import 'package:async_redux/async_redux.dart';
import 'package:models/backup_stage.dart';
import 'package:models/error_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys/backups` ▸ `restore_apply {upload, sections, mode, passphrase,
/// accept, replace_keys}`. `add` works live and answers `{done, skipped,
/// restart: false}`; `replace` stages the sections, answers `{sections,
/// restart: true}` and the broker stops: the next start applies them, and
/// Studio reconnects by itself. An answer of another shape is refused:
/// the dialog stays where it is and says so.
///
/// What goes, and whether it may, is decided here from the plan of the
/// form (`restorePlan`), whoever dispatched this: a backup of another
/// site, keys that are not this broker's without the confirmation, a
/// locked replace or nothing ticked is refused before anything is sent;
/// only the sections the plan takes go.
///
/// Once the broker answered, the upload is its own: that is recorded
/// (`applySent`) before the answer is read, so a refused answer does not
/// make closing the dialog abort an applied upload.
class ApplyRestoreAction extends Action with NonReentrant, WaitingAction {
  ApplyRestoreAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final key = '${site.root}/sys/backups';
    final upload = backups.upload;
    final plan = restorePlan(passphraseLength: passphrase?.length ?? 0);
    if (upload == null || !plan.canRun) {
      throw stepBlockedOf(key, 'restore_apply');
    }
    final mode = backups.mode;
    final Value answer;
    try {
      answer = await invokeOne(
        deps.wyrm,
        key,
        'restore_apply',
        valueOf({
          'upload': upload,
          'sections': [
            for (final s in mode.sections)
              if (plan.sent.contains(s)) s.wire,
          ],
          'mode': mode.wire,
          if (passphrase case final p? when p.isNotEmpty) 'passphrase': p,
          if (backups.acceptRights) 'accept': true,
          if (backups.replaceKeys) 'replace_keys': true,
        }),
      );
    } on StudioException catch (e) {
      // No answer came: the broker may have applied it all the same.
      if (e.error.kind == ErrorKind.reach) {
        dispatchSync(_ApplySent());
      }
      rethrow;
    }
    dispatchSync(_ApplySent(), notify: false);
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

/// The broker has (or may have) the apply: the upload is no longer
/// Studio's to drop.
class _ApplySent extends Action {
  @override
  AppState reduce() => state.copyWith.backups(applySent: true);
}
