import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';

import '../models/broker_said.dart';
import '../models/disabled.dart';
import '../models/tone.dart';
import '../overlays/backup_data.dart';

// What System is drawn from (specs/system.md), as typed values: the
// connector maps the domain into these; `SystemScreen` words them in the
// language on screen (studio-rules §3, §5).

/// A tab of System, in the order of its bar.
enum SysTab {
  overview,
  availability,
  log,
  maintenance;

  String get label => switch (this) {
    overview => S.current.sysTabOverview,
    availability => S.current.sysTabAvailability,
    log => S.current.sysTabLog,
    maintenance => S.current.sysTabMaintenance,
  };
}

/// The warm standby as System draws it (no value yet: none of these).
enum SysStandby {
  /// No standby follows the broker.
  none,
  following,

  /// Behind (`standby_lag` > 0) or a fork moved aside.
  behind;

  /// The dot of the Availability tab: amber while behind, grey with no
  /// standby, none when all is well.
  Tone? get dot => switch (this) {
    none => Tone.neutral,
    following => null,
    behind => Tone.warn,
  };
}

/// A value of `sys` drawn as a tile, with its label (its key below `sys`
/// comes with its [SysReading]).
enum SysTileKey {
  linksConnected,
  quarantined,
  packagesTotal,
  upstreamConnected,
  downstreamConnected,
  sessions,
  cpu,
  memory,
  diskFree,
  dataSize,
  aclDenied,
  auditRecords,
  standbyConnected,
  standbyLag,
  arbiterLease,
  standbyForks;

  String get label => switch (this) {
    linksConnected => S.current.mLinksConnected,
    quarantined => S.current.mInQuarantine,
    packagesTotal => S.current.sysPackages,
    upstreamConnected => S.current.sysUpstream,
    downstreamConnected => S.current.sysDownstream,
    sessions => S.current.mSessions,
    cpu => 'CPU',
    memory => S.current.mMemory,
    diskFree => S.current.mFreeDisk,
    dataSize => 'data_dir',
    aclDenied => S.current.mAclDenials,
    auditRecords => S.current.mAuditRecords,
    standbyConnected => S.current.sysStandbyConnected,
    standbyLag => S.current.sysLag,
    arbiterLease => S.current.sysArbiterLease,
    standbyForks => S.current.sysForks,
  };

  /// The tile opens the screen where it is fixed.
  bool get opens => switch (this) {
    linksConnected ||
    quarantined ||
    packagesTotal ||
    upstreamConnected ||
    downstreamConnected ||
    dataSize ||
    aclDenied ||
    auditRecords => true,
    sessions ||
    cpu ||
    memory ||
    diskFree ||
    standbyConnected ||
    standbyLag ||
    arbiterLease ||
    standbyForks => false,
  };
}

/// One value of `sys`: its key below `sys` (the tile shows it), the number
/// (none before it arrived), the node's own unit, and its description (the
/// tile's tooltip).
final class SysReading extends Equatable {
  const SysReading({required this.key, this.value, this.unit, this.about = ''});

  final String key;
  final num? value;
  final String? unit;
  final String about;

  @override
  List<Object?> get props => [key, value, unit, about];
}

/// What *Router traffic* draws: the messages, frames or bytes per second.
enum SysMeasure {
  messages,
  frames,
  bytes;

  String get label => switch (this) {
    messages => S.current.sysMessages,
    frames => S.current.sysFrames,
    bytes => S.current.sysBytes,
  };

  /// The broker serves bytes per second; the board shows kB/s.
  double get scale => switch (this) {
    messages || frames => 1,
    bytes => 0.001,
  };

  /// The unit when the node names none (and always for bytes, scaled).
  String unitOr(String? own) => switch (this) {
    messages => own ?? 'msg/s',
    frames => own ?? 'frame/s',
    bytes => 'kB/s',
  };
}

/// The rates of one traffic sample (µs since the epoch), unscaled.
final class SysRate extends Equatable {
  const SysRate(this.time, this.inward, this.outward);

  final int time;
  final double inward;
  final double outward;

  @override
  List<Object?> get props => [time, inward, outward];
}

/// The traffic trend's range, window (µs) and narrowest window.
final class SysTrendWindow extends Equatable {
  const SysTrendWindow({
    required this.rangeStart,
    required this.rangeEnd,
    required this.windowStart,
    required this.windowEnd,
    required this.minWindow,
    required this.following,
  });

  final int rangeStart;
  final int rangeEnd;
  final int windowStart;
  final int windowEnd;
  final int minWindow;

  /// The window's end follows the newest sample.
  final bool following;

  @override
  List<Object?> get props => [
    rangeStart,
    rangeEnd,
    windowStart,
    windowEnd,
    minWindow,
    following,
  ];
}

/// *Router traffic*: the measure and its two keys below `sys`, the rates
/// now, the node's unit, the ring of samples and the window on it (null
/// before two samples).
final class SysTrafficData extends Equatable {
  const SysTrafficData({
    this.measure = SysMeasure.messages,
    this.inKey = '',
    this.outKey = '',
    this.inNow,
    this.outNow,
    this.unit,
    this.samples = const [],
    this.window,
  });

  final SysMeasure measure;
  final String inKey;
  final String outKey;
  final num? inNow;
  final num? outNow;
  final String? unit;
  final List<SysRate> samples;
  final SysTrendWindow? window;

  @override
  List<Object?> get props => [
    measure,
    inKey,
    outKey,
    inNow,
    outNow,
    unit,
    samples,
    window,
  ];
}

/// A level of the broker's log.
enum SysLevel {
  error,
  warn,
  info,
  debug,
  trace;

  /// The level as the broker names it.
  String get label => name;
}

/// One line of the broker's log: its time as written and as read, level
/// (none when the record names none), target and message.
final class SysLogLine extends Equatable {
  const SysLogLine({
    this.time = '',
    this.at,
    this.level,
    this.target = '',
    this.message = '',
  });

  final String time;
  final DateTime? at;
  final SysLevel? level;
  final String target;
  final String message;

  @override
  List<Object?> get props => [time, at, level, target, message];
}

/// Why the last read of the log gave no lines: the broker refused
/// ([SysLogRefused]), or the answer is not a log ([SysLogInvalid]).
sealed class SysLogError extends Equatable {
  const SysLogError();

  /// As the log box says it.
  String get text;
}

/// The broker refused the read: its status name and its message.
final class SysLogRefused extends SysLogError {
  const SysLogRefused(this.status, this.message);

  final String status;
  final String message;

  @override
  String get text => '$status: $message';

  @override
  List<Object?> get props => [status, message];
}

/// The answer is not a log: the field at fault and why.
final class SysLogInvalid extends SysLogError {
  const SysLogInvalid(this.field, this.reason);

  final String field;
  final String reason;

  @override
  String get text => S.current.sysLogInvalid('$field: $reason');

  @override
  List<Object?> get props => [field, reason];
}

/// The Log tab: the toolbar's arguments, the lines shown and the broker's
/// own level.
final class SysLogData extends Equatable {
  const SysLogData({
    this.reason,
    this.lines = const [],
    this.held = 0,
    this.around,
    this.error,
    this.reading = false,
    this.sources = const [],
    this.source,
    this.level = SysLevel.info,
    this.filter,
    this.count = 200,
    this.auto = true,
    this.brokerLevel = SysLevel.info,
  });

  /// Why the log cannot be read (`needs config on sys`).
  final Disabled? reason;

  /// The lines shown: all read, or those near [around].
  final List<SysLogLine> lines;

  /// How many lines were read.
  final int held;

  /// The toolbar's time, `hh:mm:ss` (UTC).
  final String? around;

  /// Why the last read gave no lines.
  final SysLogError? error;

  /// A read is in flight.
  final bool reading;

  /// The links whose own log can be read.
  final List<String> sources;
  final String? source;
  final SysLevel level;
  final String? filter;

  /// The lines asked for.
  final int count;
  final bool auto;

  /// The level the broker logs at (or the one staged for it).
  final SysLevel brokerLevel;

  @override
  List<Object?> get props => [
    reason,
    lines,
    held,
    around,
    error,
    reading,
    sources,
    source,
    level,
    filter,
    count,
    auto,
    brokerLevel,
  ];
}

/// A link `clear_conns` would remove: its id and certificate CN.
final class SysStaleLink extends Equatable {
  const SysStaleLink(this.id, {this.cn});

  final String id;
  final String? cn;

  @override
  List<Object?> get props => [id, cn];
}

/// A device profile under `pub`, with its point count when read.
final class SysProfile extends Equatable {
  const SysProfile(this.name, {this.points});

  final String name;
  final int? points;

  @override
  List<Object?> get props => [name, points];
}

/// What a kept backup holds: the whole broker, one link (named), or
/// what was kept before an update or a restore.
sealed class SysBackupKind extends Equatable {
  const SysBackupKind();

  String get label;
}

final class SysBackupFull extends SysBackupKind {
  const SysBackupFull();

  @override
  String get label => S.current.bakKindFull;

  @override
  List<Object?> get props => const [];
}

/// A backup of the link [link].
final class SysBackupOfLink extends SysBackupKind {
  const SysBackupOfLink(this.link);

  final String link;

  @override
  String get label => S.current.bakKindLink(link);

  @override
  List<Object?> get props => [link];
}

final class SysBackupPreUpdate extends SysBackupKind {
  const SysBackupPreUpdate();

  @override
  String get label => S.current.bakKindPreUpdate;

  @override
  List<Object?> get props => const [];
}

final class SysBackupPreRestore extends SysBackupKind {
  const SysBackupPreRestore();

  @override
  String get label => S.current.bakKindPreRestore;

  @override
  List<Object?> get props => const [];
}

/// Where a kept backup is, as its row says it: being made (with its
/// percent), failed, being sent to a file store (with its percent), or
/// kept.
sealed class SysBackupStep extends Equatable {
  const SysBackupStep();
}

final class SysBackupRunning extends SysBackupStep {
  const SysBackupRunning(this.progress);

  /// Percent.
  final int progress;

  @override
  List<Object?> get props => [progress];
}

final class SysBackupMakeFailed extends SysBackupStep {
  const SysBackupMakeFailed();

  @override
  List<Object?> get props => const [];
}

final class SysBackupSending extends SysBackupStep {
  const SysBackupSending(this.progress);

  /// Percent.
  final int progress;

  @override
  List<Object?> get props => [progress];
}

/// Made (or not yet known to run) and not being sent: its size is shown.
final class SysBackupKept extends SysBackupStep {
  const SysBackupKept();

  @override
  List<Object?> get props => const [];
}

/// A kept backup as its row shows it.
final class SysBackupRow extends Equatable {
  const SysBackupRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.step,
    this.sections = const [],
    this.created,
    this.size = 0,
  });

  final String id;
  final String name;
  final SysBackupKind kind;
  final SysBackupStep step;
  final List<BackupPart> sections;
  final DateTime? created;

  /// Bytes.
  final int size;

  @override
  List<Object?> get props => [id, name, kind, step, sections, created, size];
}

/// The card *Backups*: the kept backups when they were read
/// ([SysBackupsRead]), else why no list is drawn.
sealed class SysBackupsData extends Equatable {
  const SysBackupsData();

  /// Why no backup is offered, or null when the backups were read.
  String? get said;
}

/// Read: the days a backup is kept and the kept backups.
final class SysBackupsRead extends SysBackupsData {
  const SysBackupsRead({
    required this.keepDays,
    this.rows = const [],
    this.unread = const [],
  });

  final int keepDays;
  final List<SysBackupRow> rows;

  /// The kept backups Studio could not read, by their node names: each
  /// is a row that says so.
  final List<String> unread;

  @override
  String? get said => null;

  @override
  List<Object?> get props => [keepDays, rows, unread];
}

/// The attributes of `sys/backups` came in a form this Studio does not
/// read: no backup is offered, no list is drawn, and the card says why.
final class SysBackupsUnreadable extends SysBackupsData {
  const SysBackupsUnreadable();

  @override
  String get said => S.current.bakNotRead;

  @override
  List<Object?> get props => const [];
}

/// The read failed: nothing is known, no list is drawn, and the card
/// offers to read again.
final class SysBackupsFailed extends SysBackupsData {
  const SysBackupsFailed();

  @override
  String get said => S.current.bakReadFailed;

  @override
  List<Object?> get props => const [];
}

/// Where the broker's update of itself is, as the card *Broker version*
/// says it.
enum SysSelfUpdate {
  /// None runs, none just ended.
  idle,

  /// Staged, or on trial after the restart.
  trial,
  rolledBack,
}

/// The card *Broker version*: what runs, what the channel offers (and
/// whether it is another release), where an update is, and whether one
/// runs or just ended.
final class SysVersionData extends Equatable {
  const SysVersionData({
    required this.version,
    required this.latest,
    this.state = SysSelfUpdate.idle,
    this.newer = false,
    this.runs = false,
  });

  final String version;
  final String latest;
  final SysSelfUpdate state;
  final bool newer;
  final bool runs;

  @override
  List<Object?> get props => [version, latest, state, newer, runs];
}

/// The Maintenance tab.
final class SysMaintData extends Equatable {
  const SysMaintData({
    this.reason,
    this.busy = false,
    this.stale = const [],
    this.profiles = const [],
    this.profilesUnlisted,
    this.backups,
    this.version,
    this.dataSize,
  });

  /// Why the user may not act on `sys` (`needs config on sys`).
  final Disabled? reason;

  /// `clear_conns` or a profile action runs.
  final bool busy;
  final List<SysStaleLink> stale;
  final List<SysProfile> profiles;

  /// The broker does not list its profiles: its answer.
  final BrokerSaidVm? profilesUnlisted;

  /// The kept backups; null for a broker without `sys/backups`.
  final SysBackupsData? backups;

  /// The broker's own update; null while it offers none.
  final SysVersionData? version;

  /// `data_size`, MiB.
  final num? dataSize;

  @override
  List<Object?> get props => [
    reason,
    busy,
    stale,
    profiles,
    profilesUnlisted,
    backups,
    version,
    dataSize,
  ];
}

/// Another workspace where a broker setting is kept.
enum SysElsewhere {
  quarantine,
  sites,
  access,
  history,

  /// The design system's gallery (development builds).
  gallery;

  String get label => switch (this) {
    quarantine => S.current.sysElsewhereLinks,
    sites => S.current.sysElsewhereSites,
    access => S.current.sysElsewhereAccess,
    history => S.current.sysElsewhereHistory,
    gallery => S.current.designGallery,
  };
}

/// What a card of the attention panel is about.
enum SysAttention {
  standbyBehind,
  linkFailed,
  quarantine,
  brokerWaiting,

  /// What waits in quarantine was not read by Studio.
  waitingNotRead,
  aclGrown,
  noStandby;

  /// Where it opens.
  String get go => switch (this) {
    standbyBehind || noStandby => S.current.sysAttnOpenAvail,
    linkFailed => S.current.sysAttnOpenLinks,
    quarantine || waitingNotRead => S.current.sysAttnOpenQuarantine,
    brokerWaiting => S.current.sysAttnOpenSites,
    aclGrown => S.current.sysAttnOpenAudit,
  };

  Tone get tone => switch (this) {
    linkFailed => Tone.bad,
    noStandby => Tone.neutral,
    standbyBehind ||
    quarantine ||
    brokerWaiting ||
    waitingNotRead ||
    aclGrown => Tone.warn,
  };
}

/// A card of the attention panel: what it is about ([kind]), with what
/// that card alone says and names.
sealed class SysAttentionData extends Equatable {
  const SysAttentionData();

  SysAttention get kind;
}

/// The standby is behind by [lag] records, or [forks] forks were moved
/// aside.
final class SysStandbyBehind extends SysAttentionData {
  const SysStandbyBehind({required this.lag, required this.forks});

  final int lag;
  final int forks;

  @override
  SysAttention get kind => SysAttention.standbyBehind;

  @override
  List<Object?> get props => [lag, forks];
}

/// The link [link] failed.
final class SysLinkFailed extends SysAttentionData {
  const SysLinkFailed(this.link);

  final String link;

  @override
  SysAttention get kind => SysAttention.linkFailed;

  @override
  List<Object?> get props => [link];
}

/// A link certificate ([cn]) waits at [node] in quarantine, first seen at
/// [since] (null: the broker did not say).
final class SysQuarantineWaiting extends SysAttentionData {
  const SysQuarantineWaiting({
    required this.node,
    required this.cn,
    this.since,
  });

  final String node;
  final String cn;
  final DateTime? since;

  @override
  SysAttention get kind => SysAttention.quarantine;

  @override
  List<Object?> get props => [node, cn, since];
}

/// A downstream broker ([cn]) waits at [node] and relays [relays] sites.
final class SysBrokerWaiting extends SysAttentionData {
  const SysBrokerWaiting({
    required this.node,
    required this.cn,
    required this.relays,
  });

  final String node;
  final String cn;
  final int relays;

  @override
  SysAttention get kind => SysAttention.brokerWaiting;

  @override
  List<Object?> get props => [node, cn, relays];
}

/// A connection ([cn]) waits at [node]; Studio could not read what it is.
final class SysWaitingNotRead extends SysAttentionData {
  const SysWaitingNotRead({required this.node, required this.cn});

  final String node;
  final String cn;

  @override
  SysAttention get kind => SysAttention.waitingNotRead;

  @override
  List<Object?> get props => [node, cn];
}

/// The ACL denials grew by [grown] since the counter was last seen at
/// [seen].
final class SysAclGrown extends SysAttentionData {
  const SysAclGrown({required this.grown, required this.seen});

  final int grown;
  final int seen;

  @override
  SysAttention get kind => SysAttention.aclGrown;

  @override
  List<Object?> get props => [grown, seen];
}

/// No standby follows the broker.
final class SysNoStandby extends SysAttentionData {
  const SysNoStandby();

  @override
  SysAttention get kind => SysAttention.noStandby;

  @override
  List<Object?> get props => const [];
}

/// The broker itself: its build and when it started.
final class SysBroker extends Equatable {
  const SysBroker({
    this.version,
    this.zenohVersion,
    this.distribution,
    this.started,
    this.uptime,
  });

  final String? version;
  final String? zenohVersion;
  final String? distribution;
  final DateTime? started;
  final Duration? uptime;

  @override
  List<Object?> get props => [
    version,
    zenohVersion,
    distribution,
    started,
    uptime,
  ];
}

/// System as the connector gives it.
final class SystemScreenVm extends Equatable {
  const SystemScreenVm({
    required this.site,
    this.connected = true,
    this.broker = const SysBroker(),
    this.tab = SysTab.overview,
    this.standby,
    this.readings = const IMapConst({}),
    this.linksTotal,
    this.failedLink,
    this.waitingLink,
    this.upstreamPeer,
    this.downstreamPeer,
    this.historySize,
    this.traffic = const SysTrafficData(),
    this.log = const SysLogData(),
    this.maintenance = const SysMaintData(),
    this.attention = const [],
  });

  final String site;

  /// The broker answers: the values are live.
  final bool connected;
  final SysBroker broker;
  final SysTab tab;

  /// The warm standby; null before `standby_connected` arrived.
  final SysStandby? standby;

  /// The tiles' values.
  final IMap<SysTileKey, SysReading> readings;

  /// `links_total`.
  final num? linksTotal;

  /// The first link whose state is failed.
  final String? failedLink;

  /// The certificate CN of the link that has waited in quarantine longest.
  final String? waitingLink;

  /// The connected brokers above and below.
  final String? upstreamPeer;
  final String? downstreamPeer;

  /// The historian's size, MiB.
  final num? historySize;
  final SysTrafficData traffic;
  final SysLogData log;
  final SysMaintData maintenance;
  final List<SysAttentionData> attention;

  /// The reading of [tile]; empty before the connector gave one.
  SysReading reading(SysTileKey tile) =>
      readings[tile] ?? const SysReading(key: '');

  /// The tile whose reading has [key] (a tile reports its key when
  /// tapped); null for none.
  SysTileKey? tileOf(String key) => readings.entries
      .where((e) => e.value.key == key)
      .map((e) => e.key)
      .firstOrNull;

  @override
  List<Object?> get props => [
    site,
    connected,
    broker,
    tab,
    standby,
    readings,
    linksTotal,
    failedLink,
    waitingLink,
    upstreamPeer,
    downstreamPeer,
    historySize,
    traffic,
    log,
    maintenance,
    attention,
  ];
}
