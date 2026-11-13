import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/restore_check.dart';
import 'package:models/send_link.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The `~meta` of `sys/backups/<id>` (`wy:backup`) as a [BackupJob]; its
/// values are laid over it by [backupLive].
BackupJob backupJobOf(String id, NodeMeta m) => BackupJob(
  id: id,
  kind: str(attrOf(m, 'kind')) ?? 'full',
  name: str(attrOf(m, 'name')) ?? id,
  sections: strings(attrOf(m, 'sections')).lock,
  sealed: str(attrOf(m, 'sealed')) ?? 'none',
  link: str(attrOf(m, 'link')) ?? '',
  by: str(attrOf(m, 'by')) ?? '',
);

int _int(Object? v, int or) => switch (v) {
  final num n => n.toInt(),
  _ => or,
};

/// [j] with the values of `sys/backups/<id>` (`status`, `progress`,
/// `step`, `size`, `sha256`, `created`, `expires`, `error`, `sent_to`,
/// `send_status`, `send_progress`, `send_error`): [value] gives the live
/// value of a leaf as plain Dart, or null when none arrived yet.
BackupJob backupLive(BackupJob j, Object? Function(String leaf) value) {
  String text(String leaf, String or) => switch (value(leaf)) {
    final String s => s,
    _ => or,
  };
  return j.copyWith(
    status: text('status', j.status),
    progress: _int(value('progress'), j.progress),
    step: text('step', j.step),
    size: _int(value('size'), j.size),
    sha256: text('sha256', j.sha256),
    created: text('created', j.created),
    expires: text('expires', j.expires),
    error: text('error', j.error),
    sentTo: text('sent_to', j.sentTo),
    sendStatus: text('send_status', j.sendStatus),
    sendProgress: _int(value('send_progress'), j.sendProgress),
    sendError: text('send_error', j.sendError),
  );
}

/// The attribute `send_links` of `sys/backups`: `[{link, folder}]`.
IList<SendLink> sendLinksOf(Value? v) => [
  if (v case VArray(:final v))
    for (final e in v)
      if (str(e['link']) case final link?)
        SendLink(link: link, folder: str(e['folder']) ?? 'backups'),
].lock;

/// The answer of `restore_check`.
RestoreCheck restoreCheckOf(Value v) => RestoreCheck(
  site: str(v['site']) ?? '',
  sameSite: boolean(v['same_site']) ?? false,
  created: str(v['created']) ?? '',
  broker: str(v['broker']) ?? '',
  sealed: str(v['sealed']) ?? 'none',
  schemas: {
    if (v['schemas'] case VMap(:final v))
      for (final e in v.entries)
        e.key: (
          integer(e.value['backup']) ?? 0,
          integer(e.value['here']) ?? 0,
        ),
  }.lock,
  sections: {
    if (v['sections'] case VMap(:final v))
      for (final e in v.entries) e.key: integer(e.value) ?? 0,
  }.lock,
  keys: str(v['keys']) ?? 'none',
  keysDiffer: strings(v['keys_differ']).lock,
  controlOpensHere: boolean(v['control_opens_here']) ?? true,
  links: {
    if (v['links'] case VMap(:final v))
      for (final e in v.entries) e.key: str(e.value) ?? '',
  }.lock,
  problems: strings(v['problems']).lock,
  notes: strings(v['notes']).lock,
);
