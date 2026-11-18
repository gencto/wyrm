import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/restore.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_backups_action.dart';

/// The arguments of `create`, `estimate` and a link's `backup`: the
/// sections in the broker's order (the always-there one first), the links
/// of the section `links` when some are unticked, the history range.
Map<String, Object?> backupArgs({
  required Iterable<BackupSection> sections,
  required Set<BackupSection> chosen,
  Iterable<String> allLinks = const [],
  Iterable<String> offLinks = const [],
  int? historyDays,
  String? passphrase,
}) {
  final off = offLinks.toSet();
  return {
    'sections': [
      for (final s in sections)
        if (chosen.contains(s) || s.always) s.wire,
    ],
    if (chosen.contains(BackupSection.links) && off.isNotEmpty)
      'links': [
        for (final l in allLinks)
          if (!off.contains(l)) l,
      ],
    if (chosen.contains(BackupSection.history) && historyDays != null)
      'history_days': historyDays,
    if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
  };
}

/// Starts a backup (ADR 0048 §3.4, §3.5): of the broker, `sys/backups` ▸
/// `create {sections, links, history_days, passphrase}`, or of the link of
/// the dialog, `sys/links/<id>` ▸ `backup {sections, history_days,
/// passphrase}`. Both answer `{id}`: a job in `sys/backups` whose values
/// the dialog then follows. An answer without an id is refused: no job is
/// opened for it.
///
/// [passphrase] is what is typed in the dialog (its own state): it is not
/// kept in the store, and the action logger prints types only. What goes
/// is decided here, from the plan of the form (`backupFormPlan`): `keys`
/// only sealed, the passphrase only where the broker takes one; a plan
/// that blocks the backup refuses it before anything is sent.
class CreateBackupAction extends Action with NonReentrant, WaitingAction {
  CreateBackupAction({this.passphrase});

  final String? passphrase;

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final link = backups.link;
    final key = link == null ? '$root/sys/backups' : '$root/sys/links/$link';
    final typed = passphrase ?? '';
    final plan = backupFormPlan(passphraseLength: typed.length);
    if (!plan.canRun) {
      throw stepBlockedOf(key, link == null ? 'create' : 'backup');
    }
    final chosen = plan.sent.unlock;
    final secret = plan.sendsPassphrase ? typed : null;
    final answer = link == null
        ? await invokeOne(
            deps.wyrm,
            key,
            'create',
            valueOf(
              backupArgs(
                sections: backups.sections,
                chosen: chosen,
                allLinks: links.view,
                offLinks: backups.offLinks,
                historyDays: backups.historyDays,
                passphrase: secret,
              ),
            ),
          )
        : await invokeOne(
            deps.wyrm,
            key,
            'backup',
            valueOf(
              backupArgs(
                sections: BackupSection.ofLink,
                chosen: chosen,
                historyDays: backups.historyDays,
                passphrase: secret,
              ),
            ),
            link,
          );
    final id = backupIdOf(answer).orRefuse(
      key: key,
      call: link == null ? 'create' : 'backup',
      thing: link,
    );
    await dispatchAndWait(RetrieveBackupsAction(quiet: true));
    return state.copyWith.backups(stage: BackupStage.job, job: id);
  }
}
