import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../models/disabled.dart';

/// The shortest passphrase the broker takes (ADR 0048 §3.4).
const minPassphrase = 12;

/// A section of a backup, as the backup dialogs word it.
enum BackupPart {
  control,
  keys,
  dataflows,
  storage,
  history,
  links,
  packages,
  config,
  settings,
  data,
  package;

  String get label => switch (this) {
    control => S.current.bakSecControl,
    keys => S.current.bakSecKeys,
    dataflows => S.current.bakSecDataflows,
    storage => S.current.bakSecStorage,
    history => S.current.bakSecHistory,
    links => S.current.bakSecLinks,
    packages => S.current.bakSecPackages,
    config => S.current.bakSecConfig,
    settings => S.current.bakSecSettings,
    data => S.current.bakSecData,
    package => S.current.bakSecPackage,
  };

  /// What the section holds; the history of a link backup ([ofLink]) is
  /// said in its own words.
  String note({required bool ofLink}) => switch (this) {
    control => S.current.bakSecControlNote,
    keys => S.current.bakSecKeysNote,
    dataflows => S.current.bakSecDataflowsNote,
    storage => S.current.bakSecStorageNote,
    history =>
      ofLink ? S.current.bakSecLinkHistoryNote : S.current.bakSecHistoryNote,
    links => S.current.bakSecLinksNote,
    packages => S.current.bakSecPackagesNote,
    config => S.current.bakSecConfigNote,
    settings => S.current.bakSecSettingsNote,
    data => S.current.bakSecDataNote,
    package => S.current.bakSecPackageNote,
  };

  /// Always in a backup: its checkbox is fixed.
  bool get always => this == control || this == settings;
}

/// Where a backup goes.
enum BackupTarget {
  computer,
  store,
  broker;

  String get label => switch (this) {
    computer => S.current.bakWhereComputer,
    store => S.current.bakWhereStore,
    broker => S.current.bakWhereBroker,
  };
}

/// How the secrets of a backup are sealed.
enum BackupSeal {
  none,
  passphrase,
  broker;

  /// The seal in words; a broker's seal names its [site].
  String said(String site) => switch (this) {
    none => S.current.bakSealedNone,
    passphrase => S.current.bakSealedPassphrase,
    broker => S.current.bakSealedBroker(site),
  };
}

/// Where the making of a backup is.
enum BackupJobView { working, done, failed }

/// Where the sending of a backup to a file store is.
enum BackupSendView { none, sending, done, failed }

/// What the primary button of a backup's dialog does.
enum BackupDo { nothing, remove, cancel, send, show, download }

/// How a restore goes.
enum RestoreHow {
  add,
  replace;

  String get label => switch (this) {
    add => S.current.rstAdd,
    replace => S.current.rstReplace,
  };
}

/// How the keys of a backup compare with the broker's.
enum RestoreKeysFound {
  none,
  same,
  differ,
  other;

  /// The keys of the file are not this broker's.
  bool get foreign => this == differ || this == other;
}

/// A link of a backup against the broker.
enum RestoreLinkFound {
  fresh,
  exists;

  String get label => switch (this) {
    fresh => S.current.rstLinkNew,
    exists => S.current.rstLinkExists,
  };
}

/// What the restore dialog shows.
enum RestoreView {
  /// The upload, the check and the choice.
  form,

  /// Added live.
  restored,

  /// A replace was staged: the broker restarts.
  restarting,
  applied,

  /// The broker put its state back.
  notApplied,

  /// The broker is back and says neither.
  unknown,

  /// The broker did not come back for this session.
  lost,
}

/// A file-store link the host lets backups go to, with its folder.
final class BackupSendTarget extends Equatable {
  const BackupSendTarget({required this.link, required this.folder});

  final String link;
  final String folder;

  @override
  List<Object?> get props => [link, folder];
}

/// What the *Back up* dialog is built from (boards `Backup`, `LinkBackup`,
/// spec `docs/design/specs/updates-backups.md` §2, §4).
final class BackupFormData extends Equatable {
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
    this.where = BackupTarget.computer,
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
  final List<BackupPart> sections;
  final Set<BackupPart> chosen;

  /// Bytes by section, when the broker gave them.
  final Map<BackupPart, int> estimate;

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
  final BackupTarget where;
  final List<BackupSendTarget> sendLinks;
  final String? sendLink;
  final List<String> connections;
  final String? sendConnection;
  final String? sendPath;
  final int keepDays;
  final Disabled? reason;
  final bool busy;

  /// Why no passphrase may be given, or null.
  String? get passphraseLocked => viaUpstream
      ? S.current.bakSecretsUpstream
      : (exportSecrets ? null : S.current.bakSecretsHost);

  bool get passphraseOk => passphraseLength >= minPassphrase;

  /// The section `keys` goes in: ticked, and a passphrase seals it.
  bool get withKeys =>
      link == null &&
      chosen.contains(BackupPart.keys) &&
      passphraseLocked == null &&
      passphraseOk;

  /// The sections that go to the broker.
  Set<BackupPart> get sent => {
    for (final s in chosen)
      if (s != BackupPart.keys || withKeys) s,
  };

  @override
  List<Object?> get props => [
    site,
    link,
    linkFacts,
    sections,
    chosen,
    estimate,
    historyDays,
    linkIds,
    offLinks,
    exportSecrets,
    viaUpstream,
    passphraseLength,
    where,
    sendLinks,
    sendLink,
    connections,
    sendConnection,
    sendPath,
    keepDays,
    reason,
    busy,
  ];
}

/// One backup as its dialog shows it.
final class BackupJobFacts extends Equatable {
  const BackupJobFacts({
    required this.name,
    required this.view,
    this.link,
    this.sections = const [],
    this.seal = BackupSeal.none,
    this.by = '',
    this.progress = 0,
    this.step,
    this.writing = false,
    this.size = 0,
    this.sha256 = '',
    this.expires,
    this.error = '',
    this.sentTo = '',
    this.send = BackupSendView.none,
    this.sendProgress = 0,
    this.sendError = '',
  });

  /// The file name.
  final String name;
  final BackupJobView view;

  /// The link of a link backup; null for a backup of the broker.
  final String? link;
  final List<BackupPart> sections;
  final BackupSeal seal;

  /// Who made it.
  final String by;

  /// Percent.
  final int progress;

  /// The section being copied, or null.
  final BackupPart? step;

  /// Every section is copied: the file is written.
  final bool writing;

  /// Bytes.
  final int size;
  final String sha256;
  final DateTime? expires;
  final String error;
  final String sentTo;
  final BackupSendView send;
  final int sendProgress;
  final String sendError;

  @override
  List<Object?> get props => [
    name,
    view,
    link,
    sections,
    seal,
    by,
    progress,
    step,
    writing,
    size,
    sha256,
    expires,
    error,
    sentTo,
    send,
    sendProgress,
    sendError,
  ];
}

/// What the dialog of one backup job is built from (boards
/// `BackupProgress`, `BackupDone`).
final class BackupJobData extends Equatable {
  const BackupJobData({
    required this.job,
    required this.site,
    this.where = BackupTarget.computer,
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

  final BackupJobFacts job;
  final String site;
  final BackupTarget where;
  final List<BackupSendTarget> sendLinks;
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
  final Disabled? reason;

  bool get hasKeys => job.sections.contains(BackupPart.keys);

  /// What the primary button does.
  BackupDo get primary {
    if (job.view == BackupJobView.failed) {
      return BackupDo.remove;
    }
    if (job.view != BackupJobView.done) {
      return BackupDo.nothing;
    }
    if (downloading) {
      return BackupDo.cancel;
    }
    if (where == BackupTarget.store && !hasKeys && sendLinks.isNotEmpty) {
      return job.send == BackupSendView.sending ||
              job.send == BackupSendView.done
          ? BackupDo.show
          : BackupDo.send;
    }
    if (where == BackupTarget.computer && savedTo == null) {
      return BackupDo.download;
    }
    return BackupDo.show;
  }

  @override
  List<Object?> get props => [
    job,
    site,
    where,
    sendLinks,
    sendLink,
    connections,
    sendConnection,
    sendPath,
    keepDays,
    downloading,
    downloaded,
    savedTo,
    sending,
    reason,
  ];
}

/// The SCHEMA of one store in a backup and on the broker.
final class RestoreSchema extends Equatable {
  const RestoreSchema({
    required this.store,
    required this.backup,
    required this.here,
  });

  final String store;
  final int backup;
  final int here;

  @override
  List<Object?> get props => [store, backup, here];
}

/// A section of a backup file with its bytes.
final class RestorePart extends Equatable {
  const RestorePart(this.part, this.bytes);

  final BackupPart part;
  final int bytes;

  @override
  List<Object?> get props => [part, bytes];
}

/// A link of a backup file against the broker.
final class RestoreLink extends Equatable {
  const RestoreLink(this.id, this.found);

  final String id;
  final RestoreLinkFound found;

  @override
  List<Object?> get props => [id, found];
}

/// What the broker found in a backup file (`restore_check`).
final class RestoreCheckData extends Equatable {
  const RestoreCheckData({
    this.site = '',
    this.sameSite = false,
    this.created,
    this.broker = '',
    this.seal = BackupSeal.none,
    this.schemas = const [],
    this.sections = const [],
    this.keys = RestoreKeysFound.none,
    this.keysDiffer = const [],
    this.controlOpensHere = true,
    this.links = const [],
    this.problems = const [],
    this.notes = const [],
  });

  final String site;
  final bool sameSite;
  final DateTime? created;
  final String broker;
  final BackupSeal seal;
  final List<RestoreSchema> schemas;
  final List<RestorePart> sections;
  final RestoreKeysFound keys;

  /// The key files that are not this broker's.
  final List<String> keysDiffer;
  final bool controlOpensHere;
  final List<RestoreLink> links;

  /// Each blocks a replace.
  final List<String> problems;
  final List<String> notes;

  @override
  List<Object?> get props => [
    site,
    sameSite,
    created,
    broker,
    seal,
    schemas,
    sections,
    keys,
    keysDiffer,
    controlOpensHere,
    links,
    problems,
    notes,
  ];
}

/// What the *Restore* dialog is built from (board `BackupRestore`).
final class RestoreData extends Equatable {
  const RestoreData({
    required this.site,
    this.fileName,
    this.size = 0,
    this.uploaded = 0,
    this.uploading = false,
    this.hasUpload = false,
    this.check,
    this.chosen = const {},
    this.mode = RestoreHow.add,
    this.modeTakes = const {},
    this.replaceKeys = false,
    this.acceptRights = false,
    this.exportSecrets = false,
    this.viaUpstream = false,
    this.passphraseLength = 0,
    this.busy = false,
    this.view = RestoreView.form,
    this.staged = const [],
    this.result,
    this.reason,
  });

  final String site;
  final String? fileName;
  final int size;
  final int uploaded;
  final bool uploading;
  final bool hasUpload;
  final RestoreCheckData? check;
  final Set<BackupPart> chosen;
  final RestoreHow mode;

  /// The sections [mode] restores (ADR 0048 §3.6).
  final Set<BackupPart> modeTakes;
  final bool replaceKeys;
  final bool acceptRights;
  final bool exportSecrets;
  final bool viaUpstream;
  final int passphraseLength;

  /// A check or an apply is in flight.
  final bool busy;
  final RestoreView view;

  /// The sections a replace staged.
  final List<BackupPart> staged;

  /// The broker's words of what it did.
  final String? result;
  final Disabled? reason;

  /// Why `keys` cannot be restored by this session, or null (the three
  /// gates of ADR 0048 §3.6 rule 1).
  String? get keysLocked => viaUpstream
      ? S.current.bakSecretsUpstream
      : (!exportSecrets
            ? S.current.bakSecretsHost
            : (passphraseLength == 0 ? S.current.rstKeysNeedPassphrase : null));

  /// Why a replace is not offered, or null.
  String? get replaceLocked => viaUpstream
      ? S.current.rstReplaceUpstream
      : ((check?.problems.isNotEmpty ?? false)
            ? S.current.rstReplaceProblems
            : null);

  bool takes(BackupPart section) =>
      modeTakes.contains(section) &&
      (section != BackupPart.keys || keysLocked == null);

  /// The sections that go to the broker.
  Set<BackupPart> get sent => {
    for (final s in chosen)
      if (takes(s)) s,
  };

  /// The keys of the file are not this broker's and are to be restored.
  bool get needsReplaceKeys =>
      sent.contains(BackupPart.keys) && (check?.keys.foreign ?? false);

  @override
  List<Object?> get props => [
    site,
    fileName,
    size,
    uploaded,
    uploading,
    hasUpload,
    check,
    chosen,
    mode,
    modeTakes,
    replaceKeys,
    acceptRights,
    exportSecrets,
    viaUpstream,
    passphraseLength,
    busy,
    view,
    staged,
    result,
    reason,
  ];
}
