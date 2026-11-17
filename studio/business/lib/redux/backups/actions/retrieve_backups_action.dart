import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_section.dart';
import 'package:models/send_link.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/decode/backup_job.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads `sys/backups` of the site (ADR 0048 §3.4): its attributes
/// (`export_secrets`, `send_links`, `sections`, `keep_days`) and each kept
/// backup by its meta. The values of a backup (`status`, `progress`, …)
/// are live values, watched by System › Maintenance.
///
/// A broker without `sys/backups` (before ADR 0048) reads as no sections:
/// the screens then offer no backup.
class RetrieveBackupsAction extends Action with WaitingAction {
  RetrieveBackupsAction({super.quiet});

  @override
  Action again() => RetrieveBackupsAction(quiet: quiet);

  AppState _none() => state.copyWith.backups(
    table: const IMapConst({}),
    view: const IListConst([]),
    sections: const IListConst([]),
  );

  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    if (root == null) {
      return null;
    }
    final api = deps.wyrm;
    final base = '$root/sys/backups';
    const none = (
      exportSecrets: false,
      sendLinks: IListConst<SendLink>([]),
      sections: IListConst<BackupSection>([]),
      keepDays: 7,
    );
    final NodeMeta meta;
    try {
      meta = await api.meta(base);
    } on WyrmException catch (e) {
      if (e.status.known != Status.notFound) {
        rethrow;
      }
      return _none();
    }
    // a `sys/backups` this client cannot read offers no backup, as a
    // broker without it; logged with the attribute at fault
    final attrs = backupsAttrsOf(meta).orWarn(base) ?? none;
    final ids = await listOf(api, base);
    // a backup this client cannot read is left out, and logged
    final jobs = [
      for (final j in await Future.wait([
        for (final c in ids)
          metaOf(api, '$base/${c.name}').then(
            (m) => backupJobOf(c.name, m).orWarn('$base/${c.name}'),
          ),
      ]))
        ?j,
    ];
    return state.copyWith.backups(
      table: IMap<String, BackupJob>.fromValues(
        values: jobs,
        keyMapper: (j) => j.id,
      ),
      view: [for (final j in jobs) j.id].lock,
      exportSecrets: attrs.exportSecrets,
      sendLinks: attrs.sendLinks,
      sections: attrs.sections,
      keepDays: attrs.keepDays,
    );
  }
}
