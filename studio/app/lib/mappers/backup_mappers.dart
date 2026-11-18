import 'package:business/redux/backups/models/backups_state.dart';
import 'package:business/wyrm/backup_plan.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:models/backup_status.dart';
import 'package:models/backup_step.dart';
import 'package:models/link_info.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_keys.dart';
import 'package:models/restore_link_state.dart';
import 'package:models/restore_mode.dart';
import 'package:models/send_link.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/overlays/backup_data.dart';

import 'link_install_mappers.dart';

// The domain of backups (`models`) as the backup dialogs draw it (`ui`):
// one exhaustive map per enum (studio-rules §3), in both directions where
// the dialog reports a choice back.

extension BackupSectionPart on BackupSection {
  BackupPart get part => switch (this) {
    BackupSection.control => BackupPart.control,
    BackupSection.keys => BackupPart.keys,
    BackupSection.dataflows => BackupPart.dataflows,
    BackupSection.storage => BackupPart.storage,
    BackupSection.history => BackupPart.history,
    BackupSection.links => BackupPart.links,
    BackupSection.packages => BackupPart.packages,
    BackupSection.config => BackupPart.config,
    BackupSection.settings => BackupPart.settings,
    BackupSection.data => BackupPart.data,
    BackupSection.package => BackupPart.package,
  };
}

extension BackupPartSection on BackupPart {
  BackupSection get section => switch (this) {
    BackupPart.control => BackupSection.control,
    BackupPart.keys => BackupSection.keys,
    BackupPart.dataflows => BackupSection.dataflows,
    BackupPart.storage => BackupSection.storage,
    BackupPart.history => BackupSection.history,
    BackupPart.links => BackupSection.links,
    BackupPart.packages => BackupSection.packages,
    BackupPart.config => BackupSection.config,
    BackupPart.settings => BackupSection.settings,
    BackupPart.data => BackupSection.data,
    BackupPart.package => BackupSection.package,
  };
}

extension BackupPlaceTarget on BackupPlace {
  BackupTarget get target => switch (this) {
    BackupPlace.computer => BackupTarget.computer,
    BackupPlace.store => BackupTarget.store,
    BackupPlace.broker => BackupTarget.broker,
  };
}

extension BackupTargetPlace on BackupTarget {
  BackupPlace get place => switch (this) {
    BackupTarget.computer => BackupPlace.computer,
    BackupTarget.store => BackupPlace.store,
    BackupTarget.broker => BackupPlace.broker,
  };
}

extension RestoreModeHow on RestoreMode {
  RestoreHow get how => switch (this) {
    RestoreMode.add => RestoreHow.add,
    RestoreMode.replace => RestoreHow.replace,
  };
}

extension RestoreHowMode on RestoreHow {
  RestoreMode get mode => switch (this) {
    RestoreHow.add => RestoreMode.add,
    RestoreHow.replace => RestoreMode.replace,
  };
}

extension BackupSealedSeal on BackupSealed {
  BackupSeal get seal => switch (this) {
    BackupSealed.none => BackupSeal.none,
    BackupSealed.passphrase => BackupSeal.passphrase,
    BackupSealed.broker => BackupSeal.broker,
  };
}

extension RestoreKeysFoundOf on RestoreKeys {
  RestoreKeysFound get found => switch (this) {
    RestoreKeys.none => RestoreKeysFound.none,
    RestoreKeys.same => RestoreKeysFound.same,
    RestoreKeys.differ => RestoreKeysFound.differ,
    RestoreKeys.other => RestoreKeysFound.other,
  };
}

extension RestoreLinkStateFound on RestoreLinkState {
  RestoreLinkFound get found => switch (this) {
    RestoreLinkState.fresh => RestoreLinkFound.fresh,
    RestoreLinkState.exists => RestoreLinkFound.exists,
  };
}

extension BackupStatusView on BackupStatus {
  /// A backup with no status yet is being made.
  BackupJobView get view => switch (this) {
    BackupStatus.unknown || BackupStatus.running => BackupJobView.working,
    BackupStatus.done => BackupJobView.done,
    BackupStatus.failed => BackupJobView.failed,
  };
}

extension BackupSendStatusView on BackupSendStatus {
  BackupSendView get view => switch (this) {
    BackupSendStatus.none => BackupSendView.none,
    BackupSendStatus.sending => BackupSendView.sending,
    BackupSendStatus.done => BackupSendView.done,
    BackupSendStatus.failed => BackupSendView.failed,
  };
}

extension BackupStageRestoreView on BackupStage {
  /// What the restore dialog shows at this stage; null for the stages of
  /// a backup (its form, its job).
  RestoreView? get restoreView => switch (this) {
    BackupStage.choose || BackupStage.link || BackupStage.job => null,
    BackupStage.restore => RestoreView.form,
    BackupStage.restored => RestoreView.restored,
    BackupStage.restarting => RestoreView.restarting,
    BackupStage.applied => RestoreView.applied,
    BackupStage.notApplied => RestoreView.notApplied,
    BackupStage.unknown => RestoreView.unknown,
    BackupStage.lost => RestoreView.lost,
  };
}

extension SendLinkTarget on SendLink {
  BackupSendTarget get target => BackupSendTarget(link: link, folder: folder);
}

extension BackupJobFactsOf on BackupJob {
  /// The backup as its dialog shows it.
  BackupJobFacts get facts => BackupJobFacts(
    name: name,
    view: status.view,
    link: kind == BackupKind.link ? link : null,
    sections: [for (final s in sections) s.part],
    seal: sealed.seal,
    by: by,
    progress: progress,
    step: switch (step) {
      BackupStepSection(:final section) => section.part,
      BackupStepNone() || BackupStepWriting() => null,
    },
    writing: step is BackupStepWriting,
    size: size,
    sha256: sha256,
    expires: expires,
    error: error,
    sentTo: sentTo,
    send: sendStatus.view,
    sendProgress: sendProgress,
    sendError: sendError,
  );
}

extension RestoreCheckDataOf on RestoreCheck {
  /// The broker's findings as the restore dialog shows them.
  RestoreCheckData get data => RestoreCheckData(
    site: site,
    sameSite: sameSite,
    created: created,
    broker: broker,
    seal: sealed.seal,
    schemas: [
      for (final MapEntry(:key, :value) in schemas.entries)
        RestoreSchema(store: key, backup: value.backup, here: value.here),
    ],
    sections: [
      for (final MapEntry(:key, :value) in sections.entries)
        RestorePart(key.part, value),
    ],
    keys: keys.found,
    keysDiffer: keysDiffer.unlock,
    controlOpensHere: controlOpensHere,
    links: [
      for (final MapEntry(:key, :value) in links.entries)
        RestoreLink(key, value.found),
    ],
    problems: problems.unlock,
    notes: notes.unlock,
  );
}

extension SecretsLockUi on SecretsLock {
  SecretsLockReason get ui => switch (this) {
    SecretsLock.viaUpstream => SecretsLockReason.viaUpstream,
    SecretsLock.hostForbids => SecretsLockReason.hostForbids,
    SecretsLock.noPassphrase => SecretsLockReason.noPassphrase,
  };
}

extension ReplaceLockUi on ReplaceLock {
  ReplaceLockReason get ui => switch (this) {
    ReplaceLock.viaUpstream => ReplaceLockReason.viaUpstream,
    ReplaceLock.problems => ReplaceLockReason.problems,
  };
}

extension BackupJobStepUi on BackupJobStep {
  BackupDo get ui => switch (this) {
    BackupJobStep.nothing => BackupDo.nothing,
    BackupJobStep.remove => BackupDo.remove,
    BackupJobStep.cancel => BackupDo.cancel,
    BackupJobStep.send => BackupDo.send,
    BackupJobStep.show => BackupDo.show,
    BackupJobStep.download => BackupDo.download,
  };
}

/// The *Back up* form as it is drawn: the state [b], what [plan] decided
/// goes to the broker, and what only the screen knows ([link]: the link
/// of a link backup when it is known, [passphraseTyped]).
BackupFormData backupFormDataOf({
  required String site,
  required BackupsState b,
  required BackupFormPlan plan,
  required bool passphraseTyped,
  LinkInfo? link,
  List<String> linkIds = const [],
  Disabled? reason,
  bool busy = false,
}) => BackupFormData(
  site: site,
  link: b.link,
  linkMode: link?.mode.ui,
  linkDriver: link?.driver,
  sections: [
    for (final s in backupSectionsOf(
      b,
      runsPackage: link?.driver.startsWith('pkg:') ?? false,
    ))
      s.part,
  ],
  chosen: {for (final s in b.chosen) s.part},
  estimate: {
    for (final MapEntry(:key, :value) in b.estimate.entries) key.part: value,
  },
  historyRange: BackupRange.ofDays(b.historyDays),
  linkIds: linkIds,
  offLinks: b.offLinks.unlock,
  secretsLock: plan.secretsLock?.ui,
  passphraseTyped: passphraseTyped,
  passphraseOk: plan.passphraseOk,
  passphraseMin: minPassphrase,
  withKeys: plan.withKeys,
  sent: {for (final s in plan.sent) s.part},
  where: b.where.target,
  sendLinks: [for (final l in b.sendLinks) l.target],
  sendLink: b.sendLink,
  connections: b.connections.unlock,
  sendConnection: b.sendConnection,
  sendPath: b.sendPath,
  keepDays: b.keepDays,
  reason: reason,
  busy: busy,
);

/// The dialog of the kept backup [job] as it is drawn; [step] is what
/// its main button does.
BackupJobData backupJobDataOf({
  required String site,
  required BackupsState b,
  required BackupJob job,
  required BackupJobStep step,
  bool sending = false,
  Disabled? reason,
}) => BackupJobData(
  job: job.facts,
  site: site,
  primary: step.ui,
  where: b.where.target,
  sendLinks: [for (final l in b.sendLinks) l.target],
  sendLink: b.sendLink,
  connections: b.connections.unlock,
  sendConnection: b.sendConnection,
  sendPath: b.sendPath,
  keepDays: b.keepDays,
  downloading: b.downloading == job.id,
  downloaded: b.downloaded,
  savedTo: b.saved[job.id],
  sending: sending,
  reason: reason,
);

/// The *Restore* form as it is drawn at [view]: the state [b] and what
/// [plan] decided goes to the broker.
RestoreData restoreDataOf({
  required String site,
  required BackupsState b,
  required RestorePlan plan,
  required RestoreView view,
  bool uploading = false,
  bool busy = false,
  Disabled? reason,
}) => RestoreData(
  site: site,
  fileName: b.uploadName,
  size: b.uploadSize,
  uploaded: b.uploaded,
  uploading: uploading,
  hasUpload: b.upload != null,
  check: b.check?.data,
  chosen: {for (final s in b.chosen) s.part},
  mode: b.mode.how,
  takes: {for (final s in plan.takes) s.part},
  sent: {for (final s in plan.sent) s.part},
  keysLock: plan.keysLock?.ui,
  replaceLock: plan.replaceLock?.ui,
  needsReplaceKeys: plan.needsReplaceKeys,
  replaceKeys: b.replaceKeys,
  acceptRights: b.acceptRights,
  busy: busy,
  view: view,
  staged: [for (final s in b.staged) s.part],
  result: b.result,
  reason: reason,
);
