import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_status.dart';
import 'package:models/send_link.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'live_fields.dart';

const _shape = 'backup';

/// The `~meta` of `sys/backups/<id>` (`wy:backup`, ADR 0048 §3.4) as a
/// [BackupJob]: `kind` (default `full`), `name` (default the id),
/// `sections`, `sealed` (default `none`), `link`, `by`. A `kind` or
/// `sealed` this client does not know, or an attribute of another shape,
/// is [Invalid] with its field. Its values are laid over it by
/// [backupLiveOf].
Decoded<BackupJob> backupJobOf(String id, NodeMeta m) {
  final attr = m.attr ?? const <String, Value>{};
  String? text(String field) => switch (attr[field]) {
    null || VNull() => null,
    VStr(:final v) => v,
    _ => throw _Bad(field, 'not a text'),
  };
  try {
    final kind = switch (text('kind')) {
      null => BackupKind.full,
      final k =>
        BackupKind.fromWire(k) ?? (throw const _Bad('kind', 'not a kind')),
    };
    final sealed = switch (text('sealed')) {
      null => BackupSealed.none,
      final s =>
        BackupSealed.fromWire(s) ?? (throw const _Bad('sealed', 'not a seal')),
    };
    final sections = switch (attr['sections']) {
      null || VNull() => const <String>[],
      VArray(:final v) => [
        for (final e in v)
          switch (e) {
            VStr(:final v) => v,
            _ => throw const _Bad(
              'sections',
              'not texts',
            ),
          },
      ],
      _ => throw const _Bad('sections', 'not an array'),
    };
    return Valid(
      BackupJob(
        id: id,
        kind: kind,
        name: text('name') ?? id,
        sections: sections.lock,
        sealed: sealed,
        link: text('link') ?? '',
        by: text('by') ?? '',
      ),
    );
  } on _Bad catch (b) {
    return Invalid(_shape, b.field, b.reason);
  }
}

/// A field of a backup's meta that is not of its shape.
final class _Bad implements Exception {
  const _Bad(this.field, this.reason);

  final String field;
  final String reason;
}

/// The leaves of `sys/backups/<id>` [backupLiveOf] reads.
const backupLeaves = [
  'status',
  'progress',
  'step',
  'size',
  'sha256',
  'created',
  'expires',
  'error',
  'sent_to',
  'send_status',
  'send_progress',
  'send_error',
];

/// [j] with the live values of `sys/backups/<id>` laid over it: `status`,
/// `progress`, `step`, `size`, `sha256`, `created`, `expires`, `error`,
/// `sent_to`, `send_status`, `send_progress`, `send_error`. [value] gives
/// a leaf's live value as plain Dart, null when none arrived (the field
/// keeps what [j] holds). A value of another shape keeps it too **and is
/// logged** with its field and [where].
BackupJob backupLiveOf(
  BackupJob j,
  Object? Function(String leaf) value,
  String where,
) {
  T keep<T>(Decoded<T?> d, T old) => d.orWarn(where) ?? old;
  Decoded<String?> text(String leaf) => liveText(value(leaf), _shape, leaf);
  Decoded<int?> whole(String leaf) => liveInt(value(leaf), _shape, leaf);
  return j.copyWith(
    status: keep(
      liveName(value('status'), BackupStatus.fromWire, _shape, 'status'),
      j.status,
    ),
    progress: keep(whole('progress'), j.progress),
    step: keep(text('step'), j.step),
    size: keep(whole('size'), j.size),
    sha256: keep(text('sha256'), j.sha256),
    created: keep(liveTime(value('created'), _shape, 'created'), j.created),
    expires: keep(liveTime(value('expires'), _shape, 'expires'), j.expires),
    error: keep(text('error'), j.error),
    sentTo: keep(text('sent_to'), j.sentTo),
    sendStatus: keep(
      liveName(
        value('send_status'),
        BackupSendStatus.fromWire,
        _shape,
        'send_status',
      ),
      j.sendStatus,
    ),
    sendProgress: keep(whole('send_progress'), j.sendProgress),
    sendError: keep(text('send_error'), j.sendError),
  );
}

/// The attribute `send_links` of `sys/backups`: `[{link, folder}]`, the
/// folder `backups` when it names none. Absent: none.
Decoded<IList<SendLink>> sendLinksOf(Value? v) => switch (v) {
  null || VNull() => const Valid(IListConst([])),
  VArray(:final v) => _sendLinks(v),
  _ => const Invalid('send links', '', 'not an array'),
};

Decoded<IList<SendLink>> _sendLinks(List<Value> rows) {
  final out = <SendLink>[];
  for (final r in rows) {
    switch (r) {
      case VMap(:final v):
        switch ((v['link'], v['folder'])) {
          case (VStr(v: final link), null || VNull()):
            out.add(SendLink(link: link));
          case (VStr(v: final link), VStr(v: final folder)):
            out.add(SendLink(link: link, folder: folder));
          case (VStr(), _):
            return const Invalid('send links', 'folder', 'not a text');
          default:
            return const Invalid('send links', 'link', 'missing');
        }
      default:
        return const Invalid('send links', '', 'not a map');
    }
  }
  return Valid(out.lock);
}

/// The attributes of `sys/backups` (ADR 0048 §3.4).
typedef BackupsAttrs = ({
  bool exportSecrets,
  IList<SendLink> sendLinks,
  IList<String> sections,
  int keepDays,
});

/// The [BackupsAttrs] of the meta of `sys/backups`: `export_secrets`
/// (default false), `send_links`, `sections` (the sections a backup may
/// hold), `keep_days` (default 7). An attribute of another shape is
/// [Invalid] with its name.
Decoded<BackupsAttrs> backupsAttrsOf(NodeMeta m) {
  final attr = m.attr ?? const <String, Value>{};
  final exportSecrets = switch (attr['export_secrets']) {
    null || VNull() => false,
    VBool(:final v) => v,
    _ => null,
  };
  if (exportSecrets == null) {
    return const Invalid('backups', 'export_secrets', 'not a bool');
  }
  final keepDays = switch (attr['keep_days']) {
    null || VNull() => 7,
    VInt(:final v) => v,
    VFloat(:final v) when v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
  if (keepDays == null) {
    return const Invalid('backups', 'keep_days', 'not a whole number');
  }
  final sections = switch (attr['sections']) {
    null || VNull() => const <String>[],
    VArray(:final v) when v.every((e) => e is VStr) => [
      for (final e in v)
        if (e case VStr(:final v)) v,
    ],
    _ => null,
  };
  if (sections == null) {
    return const Invalid('backups', 'sections', 'not texts');
  }
  return switch (sendLinksOf(attr['send_links'])) {
    Valid(value: final sendLinks) => Valid((
      exportSecrets: exportSecrets,
      sendLinks: sendLinks,
      sections: sections.lock,
      keepDays: keepDays,
    )),
    final Invalid<IList<SendLink>> i => Invalid(i.shape, i.field, i.reason),
  };
}
