import 'package:localization/localization.dart';
import 'package:models/backup_job.dart';
import 'package:models/restore_check.dart';
import 'package:models/send_link.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/overlays/task_sheet.dart';

import 'sizes.dart';

/// The shortest passphrase the broker takes (ADR 0048 §3.4).
const minPassphrase = 12;

/// What the *Back up* dialog is built from (boards `Backup`, `LinkBackup`,
/// spec `docs/design/specs/updates-backups.md` §2, §4).
final class BackupFormData {
  const BackupFormData({
    required this.site,
    required this.sections,
    required this.chosen,
    this.link,
    this.linkFacts,
    this.estimate = const {},
    this.historyDays,
    this.linkIds = const [],
    this.offLinks = const {},
    this.exportSecrets = false,
    this.viaUpstream = false,
    this.passphraseLength = 0,
    this.where = 'computer',
    this.sendLinks = const [],
    this.sendLink,
    this.connections = const [],
    this.sendConnection,
    this.sendPath,
    this.keepDays = 7,
    this.reason,
    this.busy = false,
  });

  final String site;

  /// The link of a link backup; null for the broker.
  final String? link;

  /// A link backup: what the link is (`modbus · process · package …`).
  final String? linkFacts;

  /// Every section the broker makes, in its order.
  final List<String> sections;
  final Set<String> chosen;

  /// Bytes by section, when the broker gave them.
  final Map<String, int> estimate;

  /// The last N days of history; null = all of it.
  final int? historyDays;
  final List<String> linkIds;
  final Set<String> offLinks;

  /// The host lets secrets leave the broker (`backups.export_secrets`).
  final bool exportSecrets;

  /// The session reaches the site through an upstream: it never gets
  /// `keys` or a passphrase-sealed file.
  final bool viaUpstream;

  /// How long the passphrase in the dialog is; the text itself stays in
  /// the dialog's own state.
  final int passphraseLength;
  final String where;
  final List<SendLink> sendLinks;
  final String? sendLink;
  final List<String> connections;
  final String? sendConnection;
  final String? sendPath;
  final int keepDays;
  final String? reason;
  final bool busy;

  /// Why no passphrase may be given, or null.
  String? get passphraseLocked => viaUpstream
      ? S.current.bakSecretsUpstream
      : (exportSecrets ? null : S.current.bakSecretsHost);

  bool get passphraseOk => passphraseLength >= minPassphrase;

  /// The section `keys` goes in: ticked, and a passphrase seals it.
  bool get withKeys =>
      link == null &&
      chosen.contains('keys') &&
      passphraseLocked == null &&
      passphraseOk;

  /// The sections that go to the broker.
  Set<String> get sent => {
    for (final s in chosen)
      if (s != 'keys' || withKeys) s,
  };
}

String _sectionName(String id) => switch (id) {
  'control' => S.current.bakSecControl,
  'keys' => S.current.bakSecKeys,
  'dataflows' => S.current.bakSecDataflows,
  'storage' => S.current.bakSecStorage,
  'history' => S.current.bakSecHistory,
  'links' => S.current.bakSecLinks,
  'packages' => S.current.bakSecPackages,
  'config' => S.current.bakSecConfig,
  'settings' => S.current.bakSecSettings,
  'data' => S.current.bakSecData,
  'package' => S.current.bakSecPackage,
  _ => id,
};

String _sectionNote(String id, {required bool link}) => switch (id) {
  'control' => S.current.bakSecControlNote,
  'keys' => S.current.bakSecKeysNote,
  'dataflows' => S.current.bakSecDataflowsNote,
  'storage' => S.current.bakSecStorageNote,
  'history' when link => S.current.bakSecLinkHistoryNote,
  'history' => S.current.bakSecHistoryNote,
  'links' => S.current.bakSecLinksNote,
  'packages' => S.current.bakSecPackagesNote,
  'config' => S.current.bakSecConfigNote,
  'settings' => S.current.bakSecSettingsNote,
  'data' => S.current.bakSecDataNote,
  'package' => S.current.bakSecPackageNote,
  _ => '',
};

List<SheetChip> _ranges(int? days) => [
  for (final (n, label) in [
    (7, S.current.bakLast7),
    (30, S.current.bakLast30),
    (90, S.current.bakLast90),
    (0, S.current.bakAll),
  ])
    SheetChip(id: '$n', label: label, on: (days ?? 0) == n),
];

/// The *Back up* dialog of the broker or of one link.
TaskSheetVm backupFormSheet(BackupFormData d) {
  final l = S.current;
  final isLink = d.link != null;
  final locked = d.passphraseLocked;
  final typed = d.passphraseLength > 0;
  final short = typed && !d.passphraseOk;
  final total = d.estimate.isEmpty
      ? null
      : [
          for (final s in d.sent) d.estimate[s] ?? 0,
        ].fold<int>(0, (a, b) => a + b);
  final keysReason =
      locked ?? (d.passphraseOk ? null : l.bakKeysNeedPassphrase);
  final store = d.where == 'store';
  final storeReason = d.sendLinks.isEmpty
      ? l.bakNoSendLinks
      : (d.withKeys ? l.bakKeysNeverSent : null);
  final target = d.sendLinks.where((s) => s.link == d.sendLink).firstOrNull;
  return TaskSheetVm(
    title: isLink ? l.bakTitleLink(d.link!) : l.bakTitle(d.site),
    sub: isLink ? l.bakSubLink(d.link!) : l.bakSub,
    blocks: [
      SheetLabel(l.bakWhatGoesIn),
      for (final s in d.sections)
        SheetSection(
          id: s,
          name: _sectionName(s),
          detail: _sectionNote(s, link: isLink),
          on: switch (s) {
            'control' || 'settings' => true,
            'keys' => d.chosen.contains(s) && keysReason == null,
            _ => d.chosen.contains(s),
          },
          locked: switch (s) {
            'control' || 'settings' => true,
            'keys' => keysReason != null,
            _ => false,
          },
          reason: s == 'keys' ? keysReason : null,
          tag: switch (s) {
            'control' || 'settings' => l.bakTagAlways,
            'keys' => l.bakTagPassphrase,
            'data' =>
              typed && locked == null ? l.bakTagPassphrase : l.bakTagSite,
            _ => null,
          },
          tagTone: s == 'keys' || (s == 'data' && typed && locked == null)
              ? .warn
              : .neutral,
          size: switch (d.estimate[s]) {
            final n? => bytesText(n),
            null => null,
          },
          chips: switch (s) {
            'history' => _ranges(d.historyDays),
            'links' => [
              for (final id in d.linkIds)
                SheetChip(id: id, label: id, on: !d.offLinks.contains(id)),
            ],
            _ => const [],
          },
          multi: s == 'links',
        ),
      if (d.linkFacts case final f?) ...[
        SheetFacts([FactVm(label: l.bakFactLink, value: f)]),
        SheetText(l.bakLinkRestoreNote, small: true),
      ],
      SheetField(
        id: 'passphrase',
        label: isLink ? l.bakPassphraseLink : l.bakPassphrase,
        secret: true,
        enabled: locked == null,
        error: short ? l.bakPassphraseShort(minPassphrase) : null,
        note:
            locked ?? (isLink ? l.bakPassphraseLinkNote : l.bakPassphraseNote),
      ),
      SheetChoice(
        id: 'where',
        label: l.bakWhere,
        options: [
          ('computer', l.bakWhereComputer),
          ('store', l.bakWhereStore),
          ('broker', l.bakWhereBroker),
        ],
        selected: d.where,
        reasons: {'store': ?storeReason},
        note: switch (d.where) {
          'store' => l.bakWhereStoreNote,
          'broker' => l.bakWhereBrokerNote(d.keepDays),
          _ => l.bakWhereComputerNote(d.keepDays),
        },
      ),
      if (store && storeReason == null) ...[
        SheetChoice(
          id: 'sendLink',
          label: l.bakSendLink,
          lines: true,
          options: [for (final s in d.sendLinks) (s.link, s.link)],
          selected: d.sendLink ?? '',
        ),
        if (d.sendLink != null)
          SheetChoice(
            id: 'sendConnection',
            label: l.bakSendConnection,
            lines: true,
            options: [for (final c in d.connections) (c, c)],
            selected: d.sendConnection ?? '',
            note: d.connections.isEmpty ? l.bakNoConnections : null,
          ),
        if (target != null && d.sendConnection != null) ...[
          SheetFacts([
            FactVm(
              label: l.bakSendFolder,
              value: '${d.sendConnection}/files/${target.folder}/',
              mono: true,
            ),
          ]),
          SheetField(
            id: 'sendPath',
            label: l.bakSendPath,
            value: d.sendPath,
            note: l.bakSendPathNote,
          ),
        ],
      ],
    ],
    note: total == null
        ? (isLink ? l.bakNeedsConfigLinks : l.bakNeedsConfig)
        : l.bakAbout(
            bytesText(total),
            isLink ? l.bakNeedsConfigLinks : l.bakNeedsConfig,
          ),
    secondary: l.cancel,
    primary: isLink ? l.bakDoLink(d.link!) : l.bakDo,
    primaryEnabled:
        d.reason == null &&
        !short &&
        (!store || (storeReason == null && d.sendConnection != null)),
    primaryReason:
        d.reason ??
        (short
            ? l.bakPassphraseShort(minPassphrase)
            : (store ? l.bakChooseConnection : null)),
    busy: d.busy,
  );
}

/// What the dialog of one backup job is built from (boards
/// `BackupProgress`, `BackupDone`).
final class BackupJobData {
  const BackupJobData({
    required this.job,
    required this.site,
    this.where = 'computer',
    this.sendLinks = const [],
    this.sendLink,
    this.connections = const [],
    this.sendConnection,
    this.sendPath,
    this.keepDays = 7,
    this.downloading = false,
    this.downloaded = 0,
    this.savedTo,
    this.sending = false,
    this.reason,
  });

  final BackupJob job;
  final String site;
  final String where;
  final List<SendLink> sendLinks;
  final String? sendLink;
  final List<String> connections;
  final String? sendConnection;
  final String? sendPath;
  final int keepDays;

  /// This backup is being downloaded.
  final bool downloading;
  final int downloaded;

  /// Where the last download of it went.
  final String? savedTo;

  /// The `send` action is in flight.
  final bool sending;
  final String? reason;

  bool get hasKeys => job.sections.contains('keys');

  /// What the primary button does: `download`, `cancel`, `send`, `show`,
  /// or nothing.
  String get primary {
    if (job.status == 'failed') {
      return 'remove';
    }
    if (job.status != 'done') {
      return '';
    }
    if (downloading) {
      return 'cancel';
    }
    if (where == 'store' && !hasKeys && sendLinks.isNotEmpty) {
      return job.sendStatus == 'sending' || job.sendStatus == 'done'
          ? 'show'
          : 'send';
    }
    if (where == 'computer' && savedTo == null) {
      return 'download';
    }
    return 'show';
  }
}

/// The dialog of one backup: its progress, then its result with the
/// download and the send.
TaskSheetVm backupJobSheet(BackupJobData d) {
  final l = S.current;
  final j = d.job;
  final what = j.kind == 'link' ? j.link : d.site;
  if (j.status == 'failed') {
    return TaskSheetVm(
      title: l.bakFailedTitle(what),
      sub: j.name,
      blocks: [
        SheetBanner(tone: .bad, title: l.bakFailed, text: j.error),
      ],
      secondary: l.updClose,
      primary: d.reason == null ? l.remove : null,
      primaryQuiet: true,
    );
  }
  if (j.status != 'done') {
    final at = j.sections.indexOf(j.step);
    return TaskSheetVm(
      title: l.bakProgressTitle(what),
      sub: l.bakProgressSub,
      blocks: [
        SheetBar(
          percent: j.progress,
          text: j.step.isEmpty ? null : _sectionName(j.step),
        ),
        SheetSteps([
          for (final (i, s) in j.sections.indexed)
            SheetStep(
              _sectionName(s),
              at < 0 ? .todo : (i < at ? .done : (i == at ? .now : .todo)),
            ),
        ]),
        SheetText(l.bakConsistent, small: true),
      ],
      note: '${j.progress} %',
      secondary: l.updClose,
      primary: l.bakWorking,
      primaryEnabled: false,
      busy: true,
    );
  }
  final store = d.where == 'store';
  final storeReason = d.sendLinks.isEmpty
      ? l.bakNoSendLinks
      : (d.hasKeys ? l.bakKeysNeverSent : null);
  final target = d.sendLinks.where((s) => s.link == d.sendLink).firstOrNull;
  final primary = d.primary;
  final percent = j.size == 0 ? 0 : (d.downloaded * 100 ~/ j.size);
  return TaskSheetVm(
    title: l.bakDoneTitle,
    sub: l.bakDoneSub(_date(j.expires)),
    blocks: [
      SheetBanner(
        title: l.bakSaved(j.name),
        text: l.bakSavedNote(bytesText(j.size), j.sections.length),
      ),
      SheetFacts([
        FactVm(label: 'SHA-256', value: j.sha256, mono: true),
        FactVm(
          label: l.bakFactContents,
          value: [
            for (final s in j.sections) _sectionName(s),
          ].join(', '),
        ),
        FactVm(
          label: l.bakFactSealed,
          value: switch (j.sealed) {
            'passphrase' => l.bakSealedPassphrase,
            'broker' => l.bakSealedBroker(d.site),
            _ => l.bakSealedNone,
          },
        ),
        if (j.by.isNotEmpty) FactVm(label: l.bakFactBy, value: j.by),
        if (j.sentTo.isNotEmpty && j.sendStatus == 'done')
          FactVm(label: l.bakFactSent, value: j.sentTo, mono: true),
      ]),
      if (d.hasKeys)
        SheetText(l.bakKeysWarning(d.site), small: true, tone: .warn)
      else
        SheetText(l.bakSensitive, small: true),
      if (d.downloading)
        SheetBar(
          percent: percent,
          text: l.bakDownloading(
            bytesText(d.downloaded),
            bytesText(j.size),
          ),
        )
      else if (d.savedTo case final p?)
        SheetText(l.bakSavedTo(p), tone: .good),
      if (j.sendStatus == 'sending')
        SheetBar(percent: j.sendProgress, text: l.bakSending(j.sentTo))
      else if (j.sendStatus == 'failed')
        SheetText(l.bakSendFailed(j.sendError), tone: .warn),
      if (!d.downloading && j.sendStatus != 'sending') ...[
        SheetChoice(
          id: 'where',
          label: l.bakWhere,
          options: [
            ('computer', l.bakWhereComputer),
            ('store', l.bakWhereStore),
          ],
          selected: store ? 'store' : 'computer',
          reasons: {'store': ?storeReason},
        ),
        if (store && storeReason == null) ...[
          SheetChoice(
            id: 'sendLink',
            label: l.bakSendLink,
            lines: true,
            options: [for (final s in d.sendLinks) (s.link, s.link)],
            selected: d.sendLink ?? '',
          ),
          if (d.sendLink != null)
            SheetChoice(
              id: 'sendConnection',
              label: l.bakSendConnection,
              lines: true,
              options: [for (final c in d.connections) (c, c)],
              selected: d.sendConnection ?? '',
              note: d.connections.isEmpty ? l.bakNoConnections : null,
            ),
          if (target != null && d.sendConnection != null) ...[
            SheetFacts([
              FactVm(
                label: l.bakSendFolder,
                value: '${d.sendConnection}/files/${target.folder}/',
                mono: true,
              ),
            ]),
            SheetField(
              id: 'sendPath',
              label: l.bakSendPath,
              value: d.sendPath,
              hint: j.name,
              note: l.bakSendPathNote,
            ),
          ],
        ],
        if (d.reason == null)
          SheetRow(
            divider: true,
            mono: false,
            text: l.bakRemoveRow,
            action: 'remove',
            actionLabel: l.remove,
          ),
      ],
    ],
    note: d.reason,
    secondary: l.updClose,
    primary: switch (primary) {
      'download' => l.bakDownload,
      'cancel' => l.bakCancelDownload,
      'send' => l.bakSend,
      _ => l.bakShow,
    },
    primaryQuiet: primary == 'cancel',
    primaryEnabled:
        primary == 'cancel' ||
        primary == 'show' ||
        (d.reason == null && (primary != 'send' || d.sendConnection != null)),
    primaryReason:
        d.reason ?? (primary == 'send' ? l.bakChooseConnection : null),
    busy: d.sending,
  );
}

/// An ISO 8601 time as `2026-11-20 15:40` (local), or the text as it is.
String _date(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) {
    return iso;
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// A backup's time for a list row.
String backupDate(String iso) => _date(iso);

/// What the *Restore* dialog is built from (board `BackupRestore`).
final class RestoreData {
  const RestoreData({
    required this.site,
    this.fileName,
    this.size = 0,
    this.uploaded = 0,
    this.uploading = false,
    this.hasUpload = false,
    this.check,
    this.chosen = const {},
    this.mode = 'add',
    this.replaceKeys = false,
    this.acceptRights = false,
    this.exportSecrets = false,
    this.viaUpstream = false,
    this.passphraseLength = 0,
    this.busy = false,
    this.stage = 'restore',
    this.result,
    this.reason,
  });

  final String site;
  final String? fileName;
  final int size;
  final int uploaded;
  final bool uploading;
  final bool hasUpload;
  final RestoreCheck? check;
  final Set<String> chosen;
  final String mode;
  final bool replaceKeys;
  final bool acceptRights;
  final bool exportSecrets;
  final bool viaUpstream;
  final int passphraseLength;

  /// A check or an apply is in flight.
  final bool busy;

  /// `restore`; `restored` (added live); after a replace `restarting`,
  /// then `applied`, `not-applied` (the broker put its state back),
  /// `unknown` (it is back and says neither) or `lost` (it did not come
  /// back for this session).
  final String stage;
  final String? result;
  final String? reason;

  /// Why `keys` cannot be restored by this session, or null (the three
  /// gates of ADR 0048 §3.6 rule 1).
  String? get keysLocked => viaUpstream
      ? S.current.bakSecretsUpstream
      : (!exportSecrets
            ? S.current.bakSecretsHost
            : (passphraseLength == 0 ? S.current.rstKeysNeedPassphrase : null));

  /// Why `replace` is not offered, or null.
  String? get replaceLocked => viaUpstream
      ? S.current.rstReplaceUpstream
      : ((check?.problems.isNotEmpty ?? false)
            ? S.current.rstReplaceProblems
            : null);

  /// The sections the mode takes.
  static const _add = {'links', 'storage'};
  static const _replace = {
    'control',
    'keys',
    'dataflows',
    'storage',
    'history',
    'links',
    'packages',
  };

  bool takes(String section) =>
      (mode == 'add' ? _add : _replace).contains(section) &&
      (section != 'keys' || keysLocked == null);

  /// The sections that go to the broker.
  Set<String> get sent => {
    for (final s in chosen)
      if (takes(s)) s,
  };

  /// The keys of the file are not this broker's and are to be restored.
  bool get needsReplaceKeys =>
      sent.contains('keys') &&
      (check?.keys == 'differ' || check?.keys == 'other');
}

/// The *Restore* dialog: the upload, the check's findings, the sections and
/// the mode, then what the broker answered.
TaskSheetVm restoreSheet(RestoreData d) {
  final l = S.current;
  final title = l.rstTitle(d.site);
  if (d.stage != 'restore') {
    return TaskSheetVm(
      title: title,
      sub: d.fileName,
      blocks: switch (d.stage) {
        'restarting' => [
          SheetSpinner(
            title: l.rstRestarting(d.site),
            text: l.rstRestartingNote,
          ),
          SheetFacts([
            FactVm(label: l.rstFactSections, value: d.result ?? ''),
          ]),
          SheetText(l.rstRestartingMore, small: true),
        ],
        'applied' => [SheetBanner(title: l.rstApplied, text: d.result)],
        'not-applied' => [
          SheetBanner(tone: .bad, title: l.rstNotApplied, text: d.result),
          SheetText(l.rstNotAppliedNote, small: true),
        ],
        'unknown' => [
          SheetBanner(tone: .warn, title: l.rstUnknown, text: l.rstUnknownNote),
        ],
        'lost' => [
          SheetBanner(tone: .warn, title: l.rstLost, text: l.rstLostNote),
        ],
        _ => [SheetBanner(title: l.rstAdded, text: d.result)],
      },
      secondary: l.updClose,
      primary: d.stage == 'lost' ? l.rstLogIn : null,
    );
  }
  final c = d.check;
  if (c == null) {
    final percent = d.size == 0 ? 0 : d.uploaded * 100 ~/ d.size;
    return TaskSheetVm(
      title: title,
      sub: d.fileName == null
          ? l.rstPick
          : '${d.fileName} · ${bytesText(d.size)}',
      blocks: [
        if (d.fileName == null)
          SheetText(l.rstPickNote)
        else if (!d.hasUpload)
          SheetBar(
            percent: percent,
            text: l.rstUploading(bytesText(d.uploaded), bytesText(d.size)),
          )
        else ...[
          SheetCard(title: l.rstUploaded, detail: l.rstUploadedNote),
          SheetField(
            id: 'passphrase',
            label: l.rstPassphrase,
            secret: true,
            note: l.rstPassphraseNote,
          ),
        ],
      ],
      note: d.reason ?? l.bakNeedsConfig,
      secondary: l.cancel,
      primary: d.fileName == null
          ? l.rstChoose
          : (d.hasUpload ? l.rstCheck : l.rstUploadingButton),
      primaryEnabled: d.reason == null && (d.fileName == null || d.hasUpload),
      primaryReason: d.reason,
      busy: d.busy || d.uploading,
    );
  }
  final exists = c.links.values.where((v) => v == 'exists').length;
  final fresh = c.links.length - exists;
  final older = c.schemas.entries
      .where((e) => e.value.$1 != e.value.$2)
      .map((e) => '${e.key} ${e.value.$1} → ${e.value.$2}')
      .join(', ');
  final sent = d.sent;
  final replace = d.mode == 'replace';
  return TaskSheetVm(
    title: title,
    sub: '${d.fileName ?? ''} · ${l.rstTick}',
    blocks: [
      SheetLabel(l.rstChecked),
      SheetCard(
        title: l.rstFile(c.site, c.broker),
        detail: l.rstFileNote(
          _date(c.created),
          c.sections.length,
          switch (c.sealed) {
            'passphrase' => l.bakSealedPassphrase,
            'broker' => l.bakSealedBroker(c.site),
            _ => l.bakSealedNone,
          },
        ),
      ),
      if (!c.sameSite)
        SheetCard(
          tone: .bad,
          title: l.rstOtherSite(c.site),
          detail: l.rstOtherSiteNote,
        ),
      switch (c.keys) {
        'same' => SheetCard(title: l.rstKeysSame, detail: l.rstKeysSameNote),
        'differ' => SheetCard(
          tone: .warn,
          title: l.rstKeysDiffer,
          detail: c.keysDiffer.join(', '),
        ),
        'other' => SheetCard(
          tone: .warn,
          title: l.rstKeysOther,
          detail: l.rstKeysOtherNote,
        ),
        _ => SheetCard(title: l.rstKeysNone, detail: l.rstKeysNoneNote),
      },
      if (!c.controlOpensHere)
        SheetCard(
          tone: .warn,
          title: l.rstControlOther,
          detail: l.rstControlOtherNote,
        ),
      if (older.isNotEmpty)
        SheetCard(tone: .warn, title: l.rstSchemas, detail: older),
      if (c.links.isNotEmpty)
        SheetCard(
          tone: exists > 0 ? .warn : .good,
          title: l.rstLinks(fresh, exists),
          detail: c.links.entries.map((e) => '${e.key}: ${e.value}').join(', '),
        ),
      for (final p in c.problems) SheetCard(tone: .bad, title: p),
      for (final n in c.notes) SheetCard(tone: .neutral, title: n),
      SheetLabel(l.rstInTheFile),
      for (final e in c.sections.entries)
        SheetSection(
          id: e.key,
          name: _sectionName(e.key),
          on: d.chosen.contains(e.key) && d.takes(e.key),
          locked: !d.takes(e.key),
          reason: switch (e.key) {
            'config' => l.rstConfigNever,
            'keys' when replace => d.keysLocked,
            _ when !d.takes(e.key) => l.rstNotInAdd,
            _ => null,
          },
          size: bytesText(e.value),
        ),
      SheetChoice(
        id: 'mode',
        label: l.rstHow,
        lines: true,
        options: [('replace', l.rstReplace), ('add', l.rstAdd)],
        selected: d.mode,
        reasons: {'replace': ?d.replaceLocked},
      ),
      if (d.needsReplaceKeys)
        SheetOption(
          id: 'replaceKeys',
          label: c.keys == 'other'
              ? l.rstReplaceKeysOther
              : l.rstReplaceKeys(c.keysDiffer.join(', ')),
          value: d.replaceKeys,
        ),
      SheetOption(
        id: 'accept',
        label: replace ? l.rstAcceptPackages : l.rstAcceptLinks,
        value: d.acceptRights,
      ),
      SheetField(
        id: 'passphrase',
        label: l.rstPassphrase,
        secret: true,
        note: l.rstPassphraseKept,
      ),
    ],
    note: d.reason ?? (replace ? l.rstReplaceNote : l.rstAddNote),
    secondary: l.cancel,
    primary: replace ? l.rstDoReplace : l.rstDoAdd,
    primaryEnabled:
        d.reason == null &&
        c.sameSite &&
        sent.isNotEmpty &&
        (!d.needsReplaceKeys || d.replaceKeys),
    primaryReason:
        d.reason ??
        (!c.sameSite
            ? l.rstOtherSiteNote
            : (sent.isEmpty
                  ? l.rstNothingTicked
                  : (d.needsReplaceKeys ? l.rstConfirmKeys : null))),
    busy: d.busy,
  );
}
