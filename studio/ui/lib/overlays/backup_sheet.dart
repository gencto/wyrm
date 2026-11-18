import 'package:flutter/widgets.dart';
import 'package:localization/localization.dart';

import '../containers/fact_grid.dart';
import '../models/value_changed.dart';
import 'backup_data.dart';
import 'task_sheet.dart';

// The sheets of the backup dialogs (boards `Backup*`, `LinkBackup`, spec
// `docs/design/specs/updates-backups.md` §2, §4), worded from typed
// values. Every control reports through a callback of its own type: a
// section by its [BackupPart], a place by its [BackupTarget], a mode by
// its [RestoreHow]. No control is known by a text id.

/// The choice of a file store, its connection and the path in it, shown
/// once a store is where the backup goes.
List<SheetBlock> _storeBlocks({
  required List<BackupSendTarget> sendLinks,
  required String? sendLink,
  required List<String> connections,
  required String? sendConnection,
  required String? sendPath,
  String? pathHint,
  ValueChanged<String>? onSendLink,
  ValueChanged<String>? onSendConnection,
  ValueChanged<String>? onSendPath,
}) {
  final l = S.current;
  final target = sendLinks.where((s) => s.link == sendLink).firstOrNull;
  return [
    SheetChoice(
      label: l.bakSendLink,
      lines: true,
      options: [
        for (final s in sendLinks)
          SheetChoiceOption(
            label: s.link,
            selected: s.link == sendLink,
            onPick: onSendLink == null ? null : () => onSendLink(s.link),
          ),
      ],
    ),
    if (sendLink != null)
      SheetChoice(
        label: l.bakSendConnection,
        lines: true,
        options: [
          for (final c in connections)
            SheetChoiceOption(
              label: c,
              selected: c == sendConnection,
              onPick: onSendConnection == null
                  ? null
                  : () => onSendConnection(c),
            ),
        ],
        note: connections.isEmpty ? l.bakNoConnections : null,
      ),
    if (target != null && sendConnection != null) ...[
      SheetFacts([
        FactVm(
          label: l.bakSendFolder,
          value: '$sendConnection/files/${target.folder}/',
          mono: true,
        ),
      ]),
      SheetField(
        slot: SheetSlot.backupSendPath,
        label: l.bakSendPath,
        value: sendPath,
        hint: pathHint,
        note: l.bakSendPathNote,
        onChanged: onSendPath,
      ),
    ],
  ];
}

/// The *Back up* dialog of the broker or of one link.
TaskSheetVm backupFormSheet(
  BackupFormData d, {
  Toggled<BackupPart>? onSection,
  ValueChanged<BackupRange>? onHistoryRange,
  ValueChanged<String>? onLink,
  ValueChanged<String>? onPassphrase,
  ValueChanged<BackupTarget>? onWhere,
  ValueChanged<String>? onSendLink,
  ValueChanged<String>? onSendConnection,
  ValueChanged<String>? onSendPath,
}) {
  final l = S.current;
  final isLink = d.link != null;
  final locked = d.secretsLock?.label;
  final typed = d.passphraseTyped;
  final short = typed && !d.passphraseOk;
  final total = d.estimate.isEmpty
      ? null
      : [
          for (final s in d.sent) d.estimate[s] ?? 0,
        ].fold<int>(0, (a, b) => a + b);
  final keysReason =
      locked ?? (d.passphraseOk ? null : l.bakKeysNeedPassphrase);
  final store = d.where == BackupTarget.store;
  final storeReason = d.sendLinks.isEmpty
      ? l.bakNoSendLinks
      : (d.withKeys ? l.bakKeysNeverSent : null);
  // a link's private data is sealed with the passphrase when one is given
  final dataSealed = typed && locked == null;
  return TaskSheetVm(
    title: isLink ? l.bakTitleLink(d.link!) : l.bakTitle(d.site),
    sub: isLink ? l.bakSubLink(d.link!) : l.bakSub,
    blocks: [
      SheetLabel(l.bakWhatGoesIn),
      for (final s in d.sections)
        SheetSection(
          name: s.label,
          detail: s.note(ofLink: isLink),
          on:
              s.always ||
              (d.chosen.contains(s) &&
                  (s != BackupPart.keys || keysReason == null)),
          locked: s.always || (s == BackupPart.keys && keysReason != null),
          reason: s == BackupPart.keys ? keysReason : null,
          tag: s.always
              ? l.bakTagAlways
              : switch (s) {
                  BackupPart.keys => l.bakTagPassphrase,
                  BackupPart.data =>
                    dataSealed ? l.bakTagPassphrase : l.bakTagSite,
                  _ => null,
                },
          tagTone: s == BackupPart.keys || (s == BackupPart.data && dataSealed)
              ? .warn
              : .neutral,
          size: switch (d.estimate[s]) {
            final n? => Formats.bytes(n),
            null => null,
          },
          chips: switch (s) {
            BackupPart.history => [
              for (final r in BackupRange.values)
                SheetChip(
                  label: r.label,
                  on: r == d.historyRange,
                  onTap: onHistoryRange == null
                      ? null
                      : () => onHistoryRange(r),
                ),
            ],
            BackupPart.links => [
              for (final id in d.linkIds)
                SheetChip(
                  label: id,
                  on: !d.offLinks.contains(id),
                  onTap: onLink == null ? null : () => onLink(id),
                ),
            ],
            _ => const [],
          },
          multi: s == BackupPart.links,
          onChanged: onSection == null ? null : (on) => onSection(s, on: on),
        ),
      if ((d.link, d.linkMode, d.linkDriver) case (
        final id?,
        final mode?,
        final driver?,
      )) ...[
        SheetFacts([
          FactVm(
            label: l.bakFactLink,
            value: '$id · ${mode.label} · $driver',
          ),
        ]),
        SheetText(l.bakLinkRestoreNote, small: true),
      ],
      SheetField(
        slot: SheetSlot.backupPassphrase,
        label: isLink ? l.bakPassphraseLink : l.bakPassphrase,
        secret: true,
        enabled: locked == null,
        error: short ? l.bakPassphraseShort(d.passphraseMin) : null,
        note:
            locked ?? (isLink ? l.bakPassphraseLinkNote : l.bakPassphraseNote),
        onChanged: onPassphrase,
      ),
      SheetChoice(
        label: l.bakWhere,
        options: [
          for (final t in BackupTarget.values)
            SheetChoiceOption(
              label: t.label,
              selected: t == d.where,
              reason: t == BackupTarget.store ? storeReason : null,
              onPick: onWhere == null ? null : () => onWhere(t),
            ),
        ],
        note: switch (d.where) {
          BackupTarget.store => l.bakWhereStoreNote,
          BackupTarget.broker => l.bakWhereBrokerNote(d.keepDays),
          BackupTarget.computer => l.bakWhereComputerNote(d.keepDays),
        },
      ),
      if (store && storeReason == null)
        ..._storeBlocks(
          sendLinks: d.sendLinks,
          sendLink: d.sendLink,
          connections: d.connections,
          sendConnection: d.sendConnection,
          sendPath: d.sendPath,
          onSendLink: onSendLink,
          onSendConnection: onSendConnection,
          onSendPath: onSendPath,
        ),
    ],
    note: total == null
        ? (isLink ? l.bakNeedsConfigLinks : l.bakNeedsConfig)
        : l.bakAbout(
            Formats.bytes(total),
            isLink ? l.bakNeedsConfigLinks : l.bakNeedsConfig,
          ),
    secondary: l.cancel,
    primary: isLink ? l.bakDoLink(d.link!) : l.bakDo,
    primaryEnabled:
        d.reason == null &&
        !short &&
        (!store || (storeReason == null && d.sendConnection != null)),
    primaryReason:
        d.reason?.text ??
        (short
            ? l.bakPassphraseShort(d.passphraseMin)
            : (store ? l.bakChooseConnection : null)),
    busy: d.busy,
  );
}

/// The dialog of one backup: its progress, then its result with the
/// download and the send.
TaskSheetVm backupJobSheet(
  BackupJobData d, {
  ValueChanged<BackupTarget>? onWhere,
  ValueChanged<String>? onSendLink,
  ValueChanged<String>? onSendConnection,
  ValueChanged<String>? onSendPath,
  VoidCallback? onRemove,
}) {
  final l = S.current;
  final j = d.job;
  final what = j.link ?? d.site;
  if (j.view == BackupJobView.failed) {
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
  if (j.view != BackupJobView.done) {
    // while the file is written every section is copied
    final at = j.writing
        ? j.sections.length
        : (j.step == null ? -1 : j.sections.indexOf(j.step!));
    return TaskSheetVm(
      title: l.bakProgressTitle(what),
      sub: l.bakProgressSub,
      blocks: [
        SheetBar(
          percent: j.progress,
          text: j.writing ? l.bakStepWriting : j.step?.label,
        ),
        SheetSteps([
          for (final (i, s) in j.sections.indexed)
            SheetStep(
              s.label,
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
  final store = d.where == BackupTarget.store;
  final storeReason = d.sendLinks.isEmpty
      ? l.bakNoSendLinks
      : (d.hasKeys ? l.bakKeysNeverSent : null);
  final primary = d.primary;
  final percent = j.size == 0 ? 0 : (d.downloaded * 100 ~/ j.size);
  return TaskSheetVm(
    title: l.bakDoneTitle,
    sub: l.bakDoneSub(switch (j.expires) {
      final t? => Formats.dateTime(t),
      null => '',
    }),
    blocks: [
      SheetBanner(
        title: l.bakSaved(j.name),
        text: l.bakSavedNote(Formats.bytes(j.size), j.sections.length),
      ),
      SheetFacts([
        FactVm(label: 'SHA-256', value: j.sha256, mono: true),
        FactVm(
          label: l.bakFactContents,
          value: [for (final s in j.sections) s.label].join(', '),
        ),
        FactVm(label: l.bakFactSealed, value: j.seal.said(d.site)),
        if (j.by.isNotEmpty) FactVm(label: l.bakFactBy, value: j.by),
        if (j.sentTo.isNotEmpty && j.send == BackupSendView.done)
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
            Formats.bytes(d.downloaded),
            Formats.bytes(j.size),
          ),
        )
      else if (d.savedTo case final p?)
        SheetText(l.bakSavedTo(p), tone: .good),
      if (j.send == BackupSendView.sending)
        SheetBar(percent: j.sendProgress, text: l.bakSending(j.sentTo))
      else if (j.send == BackupSendView.failed)
        SheetText(l.bakSendFailed(j.sendError), tone: .warn),
      if (!d.downloading && j.send != BackupSendView.sending) ...[
        SheetChoice(
          label: l.bakWhere,
          options: [
            for (final t in const [BackupTarget.computer, BackupTarget.store])
              SheetChoiceOption(
                label: t.label,
                selected: (t == BackupTarget.store) == store,
                reason: t == BackupTarget.store ? storeReason : null,
                onPick: onWhere == null ? null : () => onWhere(t),
              ),
          ],
        ),
        if (store && storeReason == null)
          ..._storeBlocks(
            sendLinks: d.sendLinks,
            sendLink: d.sendLink,
            connections: d.connections,
            sendConnection: d.sendConnection,
            sendPath: d.sendPath,
            pathHint: j.name,
            onSendLink: onSendLink,
            onSendConnection: onSendConnection,
            onSendPath: onSendPath,
          ),
        if (d.reason == null)
          SheetRow(
            divider: true,
            mono: false,
            text: l.bakRemoveRow,
            actionLabel: l.remove,
            onAction: onRemove,
          ),
      ],
    ],
    note: d.reason?.text,
    secondary: l.updClose,
    primary: switch (primary) {
      BackupDo.download => l.bakDownload,
      BackupDo.cancel => l.bakCancelDownload,
      BackupDo.send => l.bakSend,
      BackupDo.show || BackupDo.remove || BackupDo.nothing => l.bakShow,
    },
    primaryQuiet: primary == BackupDo.cancel,
    primaryEnabled:
        primary == BackupDo.cancel ||
        primary == BackupDo.show ||
        (d.reason == null &&
            (primary != BackupDo.send || d.sendConnection != null)),
    primaryReason:
        d.reason?.text ??
        (primary == BackupDo.send ? l.bakChooseConnection : null),
    busy: d.sending,
  );
}

/// What the broker answered to a restore, once it is no longer the form.
List<SheetBlock> _restoreEnd(RestoreData d) {
  final l = S.current;
  final staged = [for (final s in d.staged) s.label].join(', ');
  return switch (d.view) {
    RestoreView.restarting => [
      SheetSpinner(title: l.rstRestarting(d.site), text: l.rstRestartingNote),
      SheetFacts([FactVm(label: l.rstFactSections, value: staged)]),
      SheetText(l.rstRestartingMore, small: true),
    ],
    RestoreView.applied => [
      SheetBanner(title: l.rstApplied, text: d.result ?? staged),
    ],
    RestoreView.notApplied => [
      SheetBanner(tone: .bad, title: l.rstNotApplied, text: d.result),
      SheetText(l.rstNotAppliedNote, small: true),
    ],
    RestoreView.unknown => [
      SheetBanner(tone: .warn, title: l.rstUnknown, text: l.rstUnknownNote),
    ],
    RestoreView.lost => [
      SheetBanner(tone: .warn, title: l.rstLost, text: l.rstLostNote),
    ],
    RestoreView.restored || RestoreView.form => [
      SheetBanner(title: l.rstAdded, text: d.result),
    ],
  };
}

/// The *Restore* dialog: the upload, the check's findings, the sections and
/// the mode, then what the broker answered.
TaskSheetVm restoreSheet(
  RestoreData d, {
  Toggled<BackupPart>? onSection,
  ValueChanged<RestoreHow>? onMode,
  ValueChanged<bool>? onReplaceKeys,
  ValueChanged<bool>? onAccept,
  ValueChanged<String>? onPassphrase,
}) {
  final l = S.current;
  final title = l.rstTitle(d.site);
  if (d.view != RestoreView.form) {
    return TaskSheetVm(
      title: title,
      sub: d.fileName,
      blocks: _restoreEnd(d),
      secondary: l.updClose,
      primary: d.view == RestoreView.lost ? l.rstLogIn : null,
    );
  }
  final c = d.check;
  if (c == null) {
    final percent = d.size == 0 ? 0 : d.uploaded * 100 ~/ d.size;
    return TaskSheetVm(
      title: title,
      sub: d.fileName == null
          ? l.rstPick
          : '${d.fileName} · ${Formats.bytes(d.size)}',
      blocks: [
        if (d.fileName == null)
          SheetText(l.rstPickNote)
        else if (!d.hasUpload)
          SheetBar(
            percent: percent,
            text: l.rstUploading(
              Formats.bytes(d.uploaded),
              Formats.bytes(d.size),
            ),
          )
        else ...[
          SheetCard(title: l.rstUploaded, detail: l.rstUploadedNote),
          SheetField(
            slot: SheetSlot.backupPassphrase,
            label: l.rstPassphrase,
            secret: true,
            note: l.rstPassphraseNote,
            onChanged: onPassphrase,
          ),
        ],
      ],
      note: d.reason?.text ?? l.bakNeedsConfig,
      secondary: l.cancel,
      primary: d.fileName == null
          ? l.rstChoose
          : (d.hasUpload ? l.rstCheck : l.rstUploadingButton),
      primaryEnabled: d.reason == null && (d.fileName == null || d.hasUpload),
      primaryReason: d.reason?.text,
      busy: d.busy || d.uploading,
    );
  }
  final exists = c.links
      .where((x) => x.found == RestoreLinkFound.exists)
      .length;
  final fresh = c.links.length - exists;
  final older = c.schemas
      .where((s) => s.backup != s.here)
      .map((s) => '${s.store} ${s.backup} → ${s.here}')
      .join(', ');
  final sent = d.sent;
  final replace = d.mode == RestoreHow.replace;
  return TaskSheetVm(
    title: title,
    sub: '${d.fileName ?? ''} · ${l.rstTick}',
    blocks: [
      SheetLabel(l.rstChecked),
      SheetCard(
        title: l.rstFile(c.site, c.broker),
        detail: l.rstFileNote(
          switch (c.created) {
            final t? => Formats.dateTime(t),
            null => '',
          },
          c.sections.length,
          c.seal.said(c.site),
        ),
      ),
      if (!c.sameSite)
        SheetCard(
          tone: .bad,
          title: l.rstOtherSite(c.site),
          detail: l.rstOtherSiteNote,
        ),
      switch (c.keys) {
        RestoreKeysFound.same => SheetCard(
          title: l.rstKeysSame,
          detail: l.rstKeysSameNote,
        ),
        RestoreKeysFound.differ => SheetCard(
          tone: .warn,
          title: l.rstKeysDiffer,
          detail: c.keysDiffer.join(', '),
        ),
        RestoreKeysFound.other => SheetCard(
          tone: .warn,
          title: l.rstKeysOther,
          detail: l.rstKeysOtherNote,
        ),
        RestoreKeysFound.none => SheetCard(
          title: l.rstKeysNone,
          detail: l.rstKeysNoneNote,
        ),
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
          detail: c.links.map((x) => '${x.id}: ${x.found.label}').join(', '),
        ),
      for (final p in c.problems) SheetCard(tone: .bad, title: p),
      for (final n in c.notes) SheetCard(tone: .neutral, title: n),
      SheetLabel(l.rstInTheFile),
      for (final RestorePart(:part, :bytes) in c.sections)
        SheetSection(
          name: part.label,
          on: d.chosen.contains(part) && d.takes.contains(part),
          locked: !d.takes.contains(part),
          reason: part == BackupPart.config
              ? l.rstConfigNever
              : (part == BackupPart.keys && replace
                    ? d.keysLock?.label
                    : (d.takes.contains(part) ? null : l.rstNotInAdd)),
          size: Formats.bytes(bytes),
          onChanged: onSection == null ? null : (on) => onSection(part, on: on),
        ),
      SheetChoice(
        label: l.rstHow,
        lines: true,
        options: [
          for (final m in const [RestoreHow.replace, RestoreHow.add])
            SheetChoiceOption(
              label: m.label,
              selected: m == d.mode,
              reason: m == RestoreHow.replace ? d.replaceLock?.label : null,
              onPick: onMode == null ? null : () => onMode(m),
            ),
        ],
      ),
      if (d.needsReplaceKeys)
        SheetOption(
          label: c.keys == RestoreKeysFound.other
              ? l.rstReplaceKeysOther
              : l.rstReplaceKeys(c.keysDiffer.join(', ')),
          value: d.replaceKeys,
          onChanged: onReplaceKeys,
        ),
      SheetOption(
        label: replace ? l.rstAcceptPackages : l.rstAcceptLinks,
        value: d.acceptRights,
        onChanged: onAccept,
      ),
      SheetField(
        slot: SheetSlot.backupPassphrase,
        label: l.rstPassphrase,
        secret: true,
        note: l.rstPassphraseKept,
        onChanged: onPassphrase,
      ),
    ],
    note: d.reason?.text ?? (replace ? l.rstReplaceNote : l.rstAddNote),
    secondary: l.cancel,
    primary: replace ? l.rstDoReplace : l.rstDoAdd,
    primaryEnabled:
        d.reason == null &&
        c.sameSite &&
        sent.isNotEmpty &&
        (!d.needsReplaceKeys || d.replaceKeys),
    primaryReason:
        d.reason?.text ??
        (!c.sameSite
            ? l.rstOtherSiteNote
            : (sent.isEmpty
                  ? l.rstNothingTicked
                  : (d.needsReplaceKeys ? l.rstConfirmKeys : null))),
    busy: d.busy,
  );
}
