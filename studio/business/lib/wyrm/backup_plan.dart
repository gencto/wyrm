import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_status.dart';
import 'package:models/restore_mode.dart';

import '../redux/backups/models/backups_state.dart';

// What the backup dialogs send to the broker, decided here from the state
// and from the two things only the dialog knows (how long the passphrase
// typed is, and whether the session reaches the site through an
// upstream). `ui` shows these decisions; it makes none.

/// The shortest passphrase the broker takes (ADR 0048 §3.4).
const minPassphrase = 12;

/// Why this session cannot seal or restore secrets (ADR 0048 §3.6 rule
/// 1): the gates, in the order they are told.
enum SecretsLock {
  /// The session reaches the site through an upstream: it never gets
  /// `keys` or a passphrase-sealed file.
  viaUpstream,

  /// The host does not let secrets leave the broker
  /// (`backups.export_secrets`).
  hostForbids,

  /// No passphrase was typed (a restore of `keys` needs the file's).
  noPassphrase,
}

/// Why a restore cannot replace.
enum ReplaceLock {
  /// The session reaches the site through an upstream.
  viaUpstream,

  /// The check found problems; each blocks a replace.
  problems,
}

/// What the primary button of a kept backup's dialog does.
enum BackupJobStep { nothing, remove, cancel, send, show, download }

/// Why the section `keys` does not go into a backup.
enum KeysBlock {
  viaUpstream,
  hostForbids,

  /// It goes only sealed: a passphrase of [minPassphrase] characters.
  needsPassphrase,
}

/// Why a backup cannot go to a file store.
enum StoreBlock {
  /// The host lists no link for it (`backups.send_links`).
  noSendLinks,

  /// A backup with the keys is never sent.
  keysNeverSent,
}

/// Why *Back up* may not start.
enum BackupBlock {
  /// A passphrase is typed and is shorter than [minPassphrase].
  passphraseShort,

  /// It is to go to a file store, and the host lists no link for it.
  noSendLinks,

  /// It is to go to a file store, and it holds the keys.
  keysNeverSent,

  /// It is to go to a file store, and no connection is chosen.
  chooseConnection,
}

/// Why a kept backup may not be sent.
enum SendBlock { noSendLinks, keysNeverSent, chooseConnection }

/// Why *Restore* may not start.
enum RestoreBlock {
  /// No file is uploaded and checked.
  notChecked,

  /// The backup is of another site.
  otherSite,

  /// The mode is `replace`, and the session reaches the site through an
  /// upstream.
  replaceViaUpstream,

  /// The mode is `replace`, and the check found problems.
  replaceProblems,

  /// Nothing that the mode takes is ticked.
  nothingTicked,

  /// The keys of the file are not this broker's, and replacing them is
  /// not confirmed.
  confirmKeys,
}

/// The sections the backup form of [b] offers, in the broker's order: the
/// broker's own for a backup of the broker; for a link backup the link's,
/// with `package` only when the link runs one ([runsPackage]: the broker
/// refuses it for a built-in driver).
List<BackupSection> backupSectionsOf(
  BackupsState b, {
  required bool runsPackage,
}) => b.link == null
    ? b.sections.unlock
    : [
        for (final s in BackupSection.ofLink)
          if (s != BackupSection.package || runsPackage) s,
      ];

/// What *Back up* sends, for the form as it is now, and whether it may
/// start.
final class BackupFormPlan {
  const BackupFormPlan({
    required this.secretsLock,
    required this.passphraseTyped,
    required this.passphraseOk,
    required this.keysBlock,
    required this.storeBlock,
    required this.withKeys,
    required this.sent,
    required this.dropKeys,
    required this.blocked,
  });

  /// Why no passphrase may be given, or null.
  final SecretsLock? secretsLock;

  /// A passphrase is typed.
  final bool passphraseTyped;

  /// The passphrase typed is long enough.
  final bool passphraseOk;

  /// Why `keys` does not go in, or null (a backup of the broker).
  final KeysBlock? keysBlock;

  /// Why the backup cannot go to a file store, or null.
  final StoreBlock? storeBlock;

  /// The section `keys` goes in: ticked, and a passphrase seals it.
  final bool withKeys;

  /// The sections that go to the broker.
  final ISet<BackupSection> sent;

  /// `keys` is ticked and does not go: it is unticked before the call.
  final bool dropKeys;

  /// Why the backup may not start, or null.
  final BackupBlock? blocked;

  bool get canRun => blocked == null;

  /// The passphrase goes with the call (the broker takes one, and it is
  /// long enough).
  bool get sendsPassphrase => secretsLock == null && passphraseOk;

  /// A link's private data is sealed with the passphrase when the broker
  /// takes one and one is typed.
  bool get sealsData => secretsLock == null && passphraseTyped;
}

/// The plan of the backup form of [b]. [viaUpstream]: the session reaches
/// the site through an upstream; [passphraseLength]: how long the
/// passphrase in the dialog is.
BackupFormPlan backupFormPlanOf(
  BackupsState b, {
  required bool viaUpstream,
  required int passphraseLength,
}) {
  final lock = viaUpstream
      ? SecretsLock.viaUpstream
      : (b.exportSecrets ? null : SecretsLock.hostForbids);
  final ok = passphraseLength >= minPassphrase;
  final ticked = b.chosen.contains(BackupSection.keys);
  final withKeys = b.link == null && ticked && lock == null && ok;
  final storeBlock = b.sendLinks.isEmpty
      ? StoreBlock.noSendLinks
      : (withKeys ? StoreBlock.keysNeverSent : null);
  final toStore = b.where == BackupPlace.store;
  return BackupFormPlan(
    secretsLock: lock,
    passphraseTyped: passphraseLength > 0,
    passphraseOk: ok,
    keysBlock: switch (lock) {
      SecretsLock.viaUpstream => KeysBlock.viaUpstream,
      SecretsLock.hostForbids => KeysBlock.hostForbids,
      SecretsLock.noPassphrase || null => ok ? null : KeysBlock.needsPassphrase,
    },
    storeBlock: storeBlock,
    withKeys: withKeys,
    sent: {
      for (final s in b.chosen)
        if (s != BackupSection.keys || withKeys) s,
    }.lock,
    dropKeys: ticked && !withKeys,
    blocked: passphraseLength > 0 && !ok
        ? BackupBlock.passphraseShort
        : (!toStore
              ? null
              : switch (storeBlock) {
                  StoreBlock.noSendLinks => BackupBlock.noSendLinks,
                  StoreBlock.keysNeverSent => BackupBlock.keysNeverSent,
                  null =>
                    b.sendConnection == null
                        ? BackupBlock.chooseConnection
                        : null,
                }),
  );
}

/// What the dialog of a kept backup does, and whether it may.
final class BackupJobPlan {
  const BackupJobPlan({
    required this.step,
    required this.hasKeys,
    required this.storeBlock,
    required this.sendBlock,
  });

  /// What the primary button does.
  final BackupJobStep step;

  /// The backup holds the section `keys`.
  final bool hasKeys;

  /// Why it cannot go to a file store, or null.
  final StoreBlock? storeBlock;

  /// Why it may not be sent now, or null.
  final SendBlock? sendBlock;

  /// Why the primary button may not be pressed, or null: only a send
  /// can lack something.
  SendBlock? get blocked => step == BackupJobStep.send ? sendBlock : null;

  bool get canRun => blocked == null;

  /// The step changes the broker or reads the file from it: it needs the
  /// right to. Stopping a download and closing do not.
  bool get needsRights =>
      step != BackupJobStep.cancel && step != BackupJobStep.show;
}

/// The plan of the dialog of the kept backup [job] ([b]: where it is to
/// go, what is known of its download).
BackupJobPlan backupJobPlanOf(BackupsState b, BackupJob job) {
  final hasKeys = job.sections.contains(BackupSection.keys);
  final storeBlock = b.sendLinks.isEmpty
      ? StoreBlock.noSendLinks
      : (hasKeys ? StoreBlock.keysNeverSent : null);
  return BackupJobPlan(
    step: backupJobStepOf(b, job),
    hasKeys: hasKeys,
    storeBlock: storeBlock,
    sendBlock: switch (storeBlock) {
      StoreBlock.noSendLinks => SendBlock.noSendLinks,
      StoreBlock.keysNeverSent => SendBlock.keysNeverSent,
      null =>
        b.sendLink == null || b.sendConnection == null
            ? SendBlock.chooseConnection
            : null,
    },
  );
}

/// What the primary button does for the kept backup [job], with where it
/// is to go and what is known of its download ([b]).
BackupJobStep backupJobStepOf(BackupsState b, BackupJob job) {
  if (job.status == BackupStatus.failed) {
    return BackupJobStep.remove;
  }
  if (job.status != BackupStatus.done) {
    return BackupJobStep.nothing;
  }
  if (b.downloading == job.id) {
    return BackupJobStep.cancel;
  }
  final hasKeys = job.sections.contains(BackupSection.keys);
  if (b.where == BackupPlace.store && !hasKeys && b.sendLinks.isNotEmpty) {
    return job.sendStatus == BackupSendStatus.sending ||
            job.sendStatus == BackupSendStatus.done
        ? BackupJobStep.show
        : BackupJobStep.send;
  }
  if (b.where == BackupPlace.computer && !b.saved.containsKey(job.id)) {
    return BackupJobStep.download;
  }
  return BackupJobStep.show;
}

/// What *Restore* sends, for the form as it is now, and whether it may
/// start.
final class RestorePlan {
  const RestorePlan({
    required this.keysLock,
    required this.replaceLock,
    required this.takes,
    required this.sent,
    required this.drop,
    required this.needsReplaceKeys,
    required this.blocked,
  });

  /// Why `keys` cannot be restored by this session, or null.
  final SecretsLock? keysLock;

  /// Why a replace is not offered, or null.
  final ReplaceLock? replaceLock;

  /// The sections the mode restores for this session (`keys` only when
  /// nothing locks it).
  final ISet<BackupSection> takes;

  /// The sections that go to the broker: ticked, and taken.
  final ISet<BackupSection> sent;

  /// The sections ticked that do not go: unticked before the call.
  final ISet<BackupSection> drop;

  /// The keys of the file are not this broker's and are to be restored:
  /// the user confirms replacing them.
  final bool needsReplaceKeys;

  /// Why the restore may not start, or null.
  final RestoreBlock? blocked;

  bool get canRun => blocked == null;
}

/// The plan of the restore form of [b] (its mode, what is ticked, what
/// the check found).
RestorePlan restorePlanOf(
  BackupsState b, {
  required bool viaUpstream,
  required int passphraseLength,
}) {
  final keysLock = viaUpstream
      ? SecretsLock.viaUpstream
      : (!b.exportSecrets
            ? SecretsLock.hostForbids
            : (passphraseLength == 0 ? SecretsLock.noPassphrase : null));
  final takes = {
    for (final s in b.mode.sections)
      if (s != BackupSection.keys || keysLock == null) s,
  }.lock;
  final sent = b.chosen.where(takes.contains).toISet();
  final replaceLock = viaUpstream
      ? ReplaceLock.viaUpstream
      : ((b.check?.problems.isNotEmpty ?? false) ? ReplaceLock.problems : null);
  final needsReplaceKeys =
      sent.contains(BackupSection.keys) && (b.check?.keys.foreign ?? false);
  final check = b.check;
  return RestorePlan(
    keysLock: keysLock,
    replaceLock: replaceLock,
    takes: takes,
    sent: sent,
    drop: b.chosen.difference(sent),
    needsReplaceKeys: needsReplaceKeys,
    blocked: b.upload == null || check == null
        ? RestoreBlock.notChecked
        : (!check.sameSite
              ? RestoreBlock.otherSite
              : switch (b.mode == RestoreMode.replace ? replaceLock : null) {
                  ReplaceLock.viaUpstream => RestoreBlock.replaceViaUpstream,
                  ReplaceLock.problems => RestoreBlock.replaceProblems,
                  null =>
                    sent.isEmpty
                        ? RestoreBlock.nothingTicked
                        : (needsReplaceKeys && !b.replaceKeys
                              ? RestoreBlock.confirmKeys
                              : null),
                }),
  );
}
