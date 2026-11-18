import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/backups_attrs.dart';
import 'package:models/backups_read.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/backup_job.dart';
import '../../../wyrm/decode/decoded.dart';
import '../../../wyrm/decode/unreadable.dart';
import '../../../wyrm/failures.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../problems/actions/add_problem_action.dart';

/// Reads `sys/backups` of the site (ADR 0048 §3.4): its attributes
/// (`export_secrets`, `send_links`, `sections`, `keep_days`) and each kept
/// backup by its meta. The values of a backup (`status`, `progress`, …)
/// are live values, watched by System › Maintenance.
///
/// A broker without `sys/backups` (before ADR 0048) reads as
/// [BackupsRead.absent]; one whose attributes this client cannot read as
/// [BackupsRead.unreadable]. Either way no backup is offered, and the
/// screens say which it is.
///
/// A read that fails for another reason (no answer, a refusal) says
/// nothing of the broker: it leaves [BackupsRead.failed], never `absent`,
/// and the screens offer to read again (`ReloadShownAction` does too).
/// What an earlier read brought stays as it was.
class RetrieveBackupsAction extends Action with WaitingAction {
  RetrieveBackupsAction({super.quiet});

  @override
  Action again() => RetrieveBackupsAction(quiet: quiet);

  AppState _none(BackupsRead availability) => state.copyWith.backups(
    availability: availability,
    table: const IMapConst({}),
    view: const IListConst([]),
    unread: const IListConst([]),
    sections: const IListConst([]),
  );

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    try {
      return await _read(root);
    } on Exception {
      if (backups.availability != BackupsRead.read) {
        dispatchSync(_ReadFailed());
      }
      rethrow;
    }
  }

  Future<AppState?> _read(String root) async {
    final api = deps.wyrm;
    final base = '$root/sys/backups';
    final NodeMeta meta;
    try {
      meta = await api.meta(base);
    } on WyrmException catch (e) {
      if (e.status.known != Status.notFound) {
        rethrow;
      }
      return _none(BackupsRead.absent);
    }
    // A `sys/backups` whose attributes this client cannot read offers no
    // backup, and is not taken for a broker without one: the state says
    // "not read", and the user is told (a toast, a line in Problems).
    final BackupsAttrs attrs;
    switch (backupsAttrsOf(meta)..record(base)) {
      case Valid(:final value):
        attrs = value;
      case Invalid():
        dispatchSync(
          AddProblemAction(
            StudioError(
              kind: ErrorKind.broker,
              hint: ErrorHint.unreadableAnswer,
              key: base,
              call: 'meta',
              site: siteOf(base),
              quiet: true,
            ),
          ),
        );
        return _none(BackupsRead.unreadable);
    }
    final ids = await listOf(api, base);
    // A backup this client cannot read (a kind, a seal or a section it
    // does not know) stays in the list as one that was not read, and the
    // user is told which.
    final unread = Unread();
    final metas = await Future.wait([
      for (final c in ids) metaOf(api, '$base/${c.name}'),
    ]);
    final jobs = [
      for (final (i, c) in ids.indexed)
        ?unread.take(
          backupJobOf(c.name, metas[i]),
          name: c.name,
          where: '$base/${c.name}',
        ),
    ];
    if (unread.problem(key: base, call: 'list') case final p?) {
      dispatchSync(AddProblemAction(p));
    }
    return state.copyWith.backups(
      availability: BackupsRead.read,
      table: IMap<String, BackupJob>.fromValues(
        values: jobs,
        keyMapper: (j) => j.id,
      ),
      view: [for (final j in jobs) j.id].lock,
      unread: unread.names.lock,
      exportSecrets: attrs.exportSecrets,
      sendLinks: attrs.sendLinks,
      sections: attrs.sections,
      keepDays: attrs.keepDays,
    );
  }
}

/// The read of `sys/backups` failed before anything of it was known.
class _ReadFailed extends Action {
  @override
  AppState reduce() => state.copyWith.backups(availability: BackupsRead.failed);
}
