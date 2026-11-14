import 'dart:async';

import 'package:async_redux/async_redux.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_backups_action.dart';

/// The arguments of `create`, `estimate` and a link's `backup`: the
/// sections in the broker's order (the always-there one first), the links
/// of the section `links` when some are unticked, the history range.
Map<String, Object?> backupArgs({
  required Iterable<String> sections,
  required Set<String> chosen,
  Iterable<String> allLinks = const [],
  Iterable<String> offLinks = const [],
  int? historyDays,
  String? passphrase,
}) {
  final off = offLinks.toSet();
  return {
    'sections': [
      for (final s in sections)
        if (chosen.contains(s) || s == 'control' || s == 'settings') s,
    ],
    if (chosen.contains('links') && off.isNotEmpty)
      'links': [
        for (final l in allLinks)
          if (!off.contains(l)) l,
      ],
    if (chosen.contains('history') && historyDays != null)
      'history_days': historyDays,
    if (passphrase != null && passphrase.isNotEmpty) 'passphrase': passphrase,
  };
}

/// The sections of a link backup, in the broker's order.
const linkSections = ['settings', 'data', 'package', 'history'];

/// Starts a backup (ADR 0048 §3.4, §3.5): of the broker, `sys/backups` ▸
/// `create {sections, links, history_days, passphrase}`, or of the link of
/// the dialog, `sys/links/<id>` ▸ `backup {sections, history_days,
/// passphrase}`. Both answer `{id}`: a job in `sys/backups` whose values
/// the dialog then follows.
///
/// [passphrase] comes from the dialog's own state and goes nowhere else: it
/// is not kept in the store, and the action logger prints types only.
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
    final chosen = backups.chosen.unlock;
    final answer = link == null
        ? await invokeOne(
            deps.wyrm,
            '$root/sys/backups',
            'create',
            valueOf(
              backupArgs(
                sections: backups.sections,
                chosen: chosen,
                allLinks: links.view,
                offLinks: backups.offLinks,
                historyDays: backups.historyDays,
                passphrase: passphrase,
              ),
            ),
          )
        : await invokeOne(
            deps.wyrm,
            '$root/sys/links/$link',
            'backup',
            valueOf(
              backupArgs(
                sections: linkSections,
                chosen: chosen,
                historyDays: backups.historyDays,
                passphrase: passphrase,
              ),
            ),
            link,
          );
    final id = str(answer['id']);
    await dispatchAndWait(RetrieveBackupsAction(quiet: true));
    return state.copyWith.backups(stage: 'job', job: id);
  }
}
