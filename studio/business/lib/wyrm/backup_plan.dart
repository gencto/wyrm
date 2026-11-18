import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_status.dart';

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

/// What *Back up* sends, for the form as it is now.
final class BackupFormPlan {
  const BackupFormPlan({
    required this.secretsLock,
    required this.passphraseOk,
    required this.withKeys,
    required this.sent,
    required this.dropKeys,
  });

  /// Why no passphrase may be given, or null.
  final SecretsLock? secretsLock;

  /// The passphrase typed is long enough.
  final bool passphraseOk;

  /// The section `keys` goes in: ticked, and a passphrase seals it.
  final bool withKeys;

  /// The sections that go to the broker.
  final ISet<BackupSection> sent;

  /// `keys` is ticked and does not go: it is unticked before the call.
  final bool dropKeys;

  /// The passphrase goes with the call (the broker takes one, and it is
  /// long enough).
  bool get sendsPassphrase => secretsLock == null && passphraseOk;
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
  return BackupFormPlan(
    secretsLock: lock,
    passphraseOk: ok,
    withKeys: withKeys,
    sent: {
      for (final s in b.chosen)
        if (s != BackupSection.keys || withKeys) s,
    }.lock,
    dropKeys: ticked && !withKeys,
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

/// What *Restore* sends, for the form as it is now.
final class RestorePlan {
  const RestorePlan({
    required this.keysLock,
    required this.replaceLock,
    required this.takes,
    required this.sent,
    required this.drop,
    required this.needsReplaceKeys,
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
  return RestorePlan(
    keysLock: keysLock,
    replaceLock: viaUpstream
        ? ReplaceLock.viaUpstream
        : ((b.check?.problems.isNotEmpty ?? false)
              ? ReplaceLock.problems
              : null),
    takes: takes,
    sent: sent,
    drop: b.chosen.difference(sent),
    needsReplaceKeys:
        sent.contains(BackupSection.keys) && (b.check?.keys.foreign ?? false),
  );
}
