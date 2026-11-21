import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';

import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../models/disabled.dart';
import '../models/link_run_mode.dart';
import '../models/tone.dart';

/// A tab of Links, as drawn.
enum LinksTabKey {
  local,
  updates,
  remote,
  quarantine;

  String get label => switch (this) {
    local => S.current.onThisBroker,
    updates => S.current.updTab,
    remote => S.current.onOtherDevices,
    quarantine => S.current.quarantine,
  };
}

/// The state of a link, as drawn: its word and its tone.
enum LinkStateWord {
  installed,
  starting,
  connected,
  stopping,
  stopped,
  failed;

  String get label => switch (this) {
    installed => S.current.stateInstalled,
    starting => S.current.stateStarting,
    connected => S.current.stateConnected,
    stopping => S.current.stateStopping,
    stopped => S.current.stateStopped,
    failed => S.current.stateFailed,
  };

  Tone get tone => switch (this) {
    connected => Tone.good,
    starting || stopping => Tone.warn,
    failed => Tone.bad,
    installed || stopped => Tone.neutral,
  };
}

/// An action card of the Links inspector: its icon and the broker's name
/// of what it runs ([code], in mono). Its words come from `LinksScreen`.
enum LinkAct {
  stop(AppIcon.actionStop, 'stop'),
  start(AppIcon.actionPlay, 'start'),
  log(AppIcon.actionLog, 'get_log'),
  params(AppIcon.actionEdit, 'update'),
  history(AppIcon.actionHist, 'history · rollback'),
  secrets(AppIcon.actionKey, 'set_secret'),
  grant(AppIcon.actionGrant, 'grant'),
  updateTo(AppIcon.actionUp, 'update'),
  updateFromFile(AppIcon.actionUp, 'install_zip'),
  versions(AppIcon.actionHist, 'rollback'),
  builtIn(AppIcon.actionLock, null),
  backup(AppIcon.actionHist, 'backup'),
  remove(AppIcon.actionTrash, 'remove'),
  grants(AppIcon.actionGrant, 'grant'),
  deauthorize(AppIcon.actionBlock, 'deauthorize'),
  removeForGood(AppIcon.actionTrash, 'remove'),
  deviceRun(AppIcon.actionPlay, null),
  deviceUpgrade(AppIcon.actionUp, null);

  const LinkAct(this.icon, this.code);

  final AppIcon icon;
  final String? code;
}

/// A dialog of a link that Links opens with the widget's context.
enum LinkDialog { log, params, history, secrets, grant, backup }

/// A link dialog asked for: which one, for which link.
final class LinkDialogAsk extends Equatable {
  const LinkDialogAsk(this.dialog, this.link);

  final LinkDialog dialog;
  final String link;

  @override
  List<Object?> get props => [dialog, link];
}

/// A tab of Links with its count; null [count] for none.
final class LinksTabData extends Equatable {
  const LinksTabData(this.tab, this.count);

  final LinksTabKey tab;
  final int count;

  @override
  List<Object?> get props => [tab, count];
}

/// The package a link runs, as its row and inspector say it.
final class LinkPackageData extends Equatable {
  const LinkPackageData({
    required this.name,
    required this.version,
    this.source,
    this.sha256,
    this.wasm = false,
    this.latest = '',
    this.updateAvailable = false,
    this.versions = false,
    this.checking = false,
    this.peers = 1,
  });

  final String name;
  final String version;

  /// `repository official`, `zip upload`: its first word is shown.
  final String? source;
  final String? sha256;

  /// A WASM component: the link runs as WASM whatever its mode.
  final bool wasm;

  /// The version in the repository; empty for a custom package.
  final String latest;
  final bool updateAvailable;

  /// It was updated, or its links have restore points: *Versions and
  /// restore points* is offered.
  final bool versions;

  /// The broker checks its last update.
  final bool checking;

  /// How many links run it.
  final int peers;

  bool get official => latest.isNotEmpty;

  @override
  List<Object?> get props => [
    name,
    version,
    source,
    sha256,
    wasm,
    latest,
    updateAvailable,
    versions,
    checking,
    peers,
  ];
}

/// A link of Links: a row of a table and, selected, its inspector.
final class LinkData extends Equatable {
  const LinkData({
    required this.id,
    required this.driver,
    required this.mode,
    required this.state,
    this.package,
    this.device,
    this.note,
    this.certificateCn,
    this.restorePoints = 0,
    this.reason,
  });

  final String id;

  /// The driver it runs (`modbus`, `pkg:<name>`).
  final String driver;
  final LinkRunMode mode;
  final LinkStateWord state;

  /// The package it runs; null for a built-in driver.
  final LinkPackageData? package;

  /// An external link's device address and name.
  final String? device;
  final String? note;
  final String? certificateCn;
  final int restorePoints;

  /// Why the user may not change it; null when they may.
  final Disabled? reason;

  /// How it runs, as said: a WASM package runs as WASM.
  LinkRunMode get runsAs => package?.wasm ?? false ? LinkRunMode.wasm : mode;

  @override
  List<Object?> get props => [
    id,
    driver,
    mode,
    state,
    package,
    device,
    note,
    certificateCn,
    restorePoints,
    reason,
  ];
}

/// A connection waiting in quarantine: a link ([QuarantineLinkData]), a
/// downstream broker ([QuarantineBrokerData]), or an entry Studio could
/// not read ([QuarantineNotReadData]; the row says so).
sealed class QuarantineData extends Equatable {
  const QuarantineData({required this.node, required this.cn});

  final String node;
  final String cn;
}

/// A link's certificate.
final class QuarantineLinkData extends QuarantineData {
  const QuarantineLinkData({
    required super.node,
    required super.cn,
    this.from,
    this.firstSeen,
    this.deauthorized = false,
    this.fields,
    this.reason,
  });

  final String? from;
  final DateTime? firstSeen;
  final bool deauthorized;

  /// The form of its `approve`; null when the broker offers none.
  final List<ParamFieldVm>? fields;

  /// Why the user may not decide; null when they may.
  final Disabled? reason;

  @override
  List<Object?> get props => [
    node,
    cn,
    from,
    firstSeen,
    deauthorized,
    fields,
    reason,
  ];
}

/// A downstream broker asking for Authorize: the sites it relays and the
/// key hash to compare.
final class QuarantineBrokerData extends QuarantineData {
  const QuarantineBrokerData({
    required super.node,
    required super.cn,
    this.from,
    this.firstSeen,
    this.via = const [],
    this.key,
    this.fields,
    this.reason,
  });

  final String? from;
  final DateTime? firstSeen;
  final List<String> via;
  final String? key;

  /// The form of its `approve`; null when the broker offers none.
  final List<ParamFieldVm>? fields;

  /// Why the user may not decide; null when they may.
  final Disabled? reason;

  @override
  List<Object?> get props => [
    node,
    cn,
    from,
    firstSeen,
    via,
    key,
    fields,
    reason,
  ];
}

/// An entry answered in a form Studio does not read: what waits is not
/// known, and no Authorize is offered for it.
final class QuarantineNotReadData extends QuarantineData {
  const QuarantineNotReadData({required super.node, required super.cn});

  @override
  List<Object?> get props => [node, cn];
}

/// Which screen the update sheet shows, with what that screen alone
/// needs.
sealed class LinkUpdateStage extends Equatable {
  const LinkUpdateStage();
}

/// The review before an update.
final class LinkUpdateReviewStage extends LinkUpdateStage {
  const LinkUpdateReviewStage();

  @override
  List<Object?> get props => const [];
}

/// An update runs. Once the broker answered and checks it, [checked] is
/// that update; until then the broker tells nothing of its steps.
final class LinkUpdateProgressStage extends LinkUpdateStage {
  const LinkUpdateProgressStage({this.checked});

  final LinkUpdateReport? checked;

  @override
  List<Object?> get props => [checked];
}

/// How the last update or rollback ended.
final class LinkUpdateResultStage extends LinkUpdateStage {
  const LinkUpdateResultStage(this.report);

  final LinkUpdateReport report;

  @override
  List<Object?> get props => [report];
}

/// A package never updated here: its restore points alone.
final class LinkUpdatePointsStage extends LinkUpdateStage {
  const LinkUpdatePointsStage();

  @override
  List<Object?> get props => const [];
}

/// The version kept for a rollback, until when, and what the sheet does
/// with it.
final class LinkKeptVersion extends Equatable {
  const LinkKeptVersion({
    required this.version,
    required this.until,
    this.offered = false,
    this.allowed = false,
  });

  final String version;
  final DateTime until;

  /// The result offers the rollback first: the update failed, or ran with
  /// nodes gone.
  final bool offered;

  /// This user may roll back to it.
  final bool allowed;

  @override
  List<Object?> get props => [version, until, offered, allowed];
}

/// How the last update of a package ended, as drawn: its check runs, it
/// ran, it was rolled back, it failed, or it ended in a way this Studio
/// does not know ([LinkUpdateUnknown], with the broker's own word).
sealed class LinkUpdateEnd extends Equatable {
  const LinkUpdateEnd();
}

final class LinkUpdateChecking extends LinkUpdateEnd {
  const LinkUpdateChecking();

  @override
  List<Object?> get props => const [];
}

final class LinkUpdateOk extends LinkUpdateEnd {
  const LinkUpdateOk();

  @override
  List<Object?> get props => const [];
}

final class LinkUpdateRolledBack extends LinkUpdateEnd {
  const LinkUpdateRolledBack();

  @override
  List<Object?> get props => const [];
}

final class LinkUpdateFailed extends LinkUpdateEnd {
  const LinkUpdateFailed();

  @override
  List<Object?> get props => const [];
}

/// An end this Studio does not know: the broker's own [word] for it.
final class LinkUpdateUnknown extends LinkUpdateEnd {
  const LinkUpdateUnknown(this.word);

  final String word;

  @override
  List<Object?> get props => [word];
}

/// What the primary button of the update sheet does.
enum LinkUpdateNext { update, file, rollback, log, open }

/// The last update or rollback of a package.
final class LinkUpdateReport extends Equatable {
  const LinkUpdateReport({
    required this.from,
    required this.to,
    required this.at,
    this.end,
    this.kept = 0,
    this.added = 0,
    this.gone = 0,
    this.newKeys = const [],
    this.goneKeys = const [],
    this.reason = '',
    this.links = const [],
    this.restorePoint = false,
  });

  final String from;
  final String to;
  final DateTime at;

  /// How it ended; null when the broker says nothing of it.
  final LinkUpdateEnd? end;
  final int kept;
  final int added;
  final int gone;
  final List<String> newKeys;
  final List<String> goneKeys;
  final String reason;
  final List<String> links;
  final bool restorePoint;

  @override
  List<Object?> get props => [
    from,
    to,
    at,
    end,
    kept,
    added,
    gone,
    newKeys,
    goneKeys,
    reason,
    links,
    restorePoint,
  ];
}

/// A restore point of a link.
final class LinkPointData extends Equatable {
  const LinkPointData({
    required this.link,
    required this.version,
    required this.at,
    required this.size,
  });

  final String link;

  /// The version it ran; empty for a point taken before a restore.
  final String version;
  final DateTime at;
  final int size;

  @override
  List<Object?> get props => [link, version, at, size];
}

/// Why a broker offers no backup.
enum BackupsOff {
  /// It has no `sys/backups` (a wyrmd before ADR 0048).
  absent,

  /// It has one, in a form this Studio does not read.
  unreadable,

  /// Whether it has one was not read yet.
  notReadYet,

  /// The read failed: whether it has one is not known.
  readFailed;

  String get label => switch (this) {
    absent => S.current.bakNoBackups,
    unreadable => S.current.bakNotRead,
    notReadYet => S.current.bakNotReadYet,
    readFailed => S.current.bakReadFailed,
  };
}

/// The update sheet of one package, as typed values.
final class LinkUpdateData extends Equatable {
  const LinkUpdateData({
    required this.name,
    required this.version,
    required this.stage,
    required this.links,
    this.latest = '',
    this.official = true,
    this.wasm = false,
    this.title,
    this.summary,
    this.takePoint = true,
    this.autoRollback = true,
    this.acceptNew = false,
    this.changesState = false,
    this.stateFormat = 1,
    this.asks,
    this.said,
    this.busy = false,
    this.rollingBack = false,
    this.kept,
    this.points = const [],
    this.queue = const [],
    this.reason,
    this.next,
  });

  final String name;
  final String version;
  final LinkUpdateStage stage;
  final List<String> links;
  final String latest;
  final bool official;

  /// A WASM package: its links start hot.
  final bool wasm;
  final String? title;
  final String? summary;
  final bool takePoint;
  final bool autoRollback;
  final bool acceptNew;
  final bool changesState;
  final int stateFormat;
  final String? asks;
  final String? said;
  final bool busy;
  final bool rollingBack;

  /// The version kept for a rollback; null when none is kept.
  final LinkKeptVersion? kept;
  final List<LinkPointData> points;
  final List<String> queue;
  final Disabled? reason;
  final LinkUpdateNext? next;

  @override
  List<Object?> get props => [
    name,
    version,
    stage,
    links,
    latest,
    official,
    wasm,
    title,
    summary,
    takePoint,
    autoRollback,
    acceptNew,
    changesState,
    stateFormat,
    asks,
    said,
    busy,
    rollingBack,
    kept,
    points,
    queue,
    reason,
    next,
  ];
}

/// Everything Links draws, as typed values: `LinksScreen` words them.
final class LinksScreenVm extends Equatable {
  const LinksScreenVm({
    required this.site,
    required this.root,
    required this.tab,
    required this.tabs,
    this.brokerVersion,
    this.addReason,
    this.updateAll = false,
    this.local = const [],
    this.toUpdate = const [],
    this.remote = const [],
    this.waiting = const [],
    this.loading = false,
    this.selectedLink,
    this.selectedEntry,
    this.updating,
    this.holdUnknown = false,
    this.allowAll = false,
    this.admissionReason,
    this.backupsOff,
    this.busy = false,
    this.sheet,
  });

  final String site;

  /// `wy/<site>`: the root of the site's keys.
  final String root;

  /// `sys/version` of the broker: the version of its built-in drivers.
  final String? brokerVersion;
  final LinksTabKey tab;
  final List<LinksTabData> tabs;

  /// Why the user may not install or update; null when they may.
  final Disabled? addReason;

  /// *Update all official…* is offered.
  final bool updateAll;
  final List<LinkData> local;

  /// The rows of Updates.
  final List<LinkData> toUpdate;
  final List<LinkData> remote;
  final List<QuarantineData> waiting;

  /// The links are read and none is held yet.
  final bool loading;
  final String? selectedLink;
  final String? selectedEntry;

  /// The package whose update sheet is open.
  final String? updating;
  final bool holdUnknown;
  final bool allowAll;
  final Disabled? admissionReason;

  /// The broker has `sys/backups` (ADR 0048).
  /// Why the link cannot be backed up from here; null: it can.
  final BackupsOff? backupsOff;
  final bool busy;
  final LinkUpdateData? sheet;

  @override
  List<Object?> get props => [
    site,
    root,
    brokerVersion,
    tab,
    tabs,
    addReason,
    updateAll,
    local,
    toUpdate,
    remote,
    waiting,
    loading,
    selectedLink,
    selectedEntry,
    updating,
    holdUnknown,
    allowAll,
    admissionReason,
    backupsOff,
    busy,
    sheet,
  ];
}
