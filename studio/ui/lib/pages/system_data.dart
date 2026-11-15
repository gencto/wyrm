import 'package:equatable/equatable.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:localization/localization.dart';

import '../models/tone.dart';

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

/// Why the last read of the log gave no lines: the broker refused (its
/// status name and message), or the answer is not a log (the field and
/// why).
final class SysLogError extends Equatable {
  const SysLogError.refused(this.status, this.message) : invalid = false;
  const SysLogError.invalid(String field, String reason)
    : status = field,
      message = reason,
      invalid = true;

  final bool invalid;

  /// The status name; for an [invalid] answer, the field at fault.
  final String status;

  /// The broker's message; for an [invalid] answer, why.
  final String message;

  /// As the log box says it.
  String get text => invalid
      ? S.current.sysLogInvalid('$status: $message')
      : '$status: $message';

  @override
  List<Object?> get props => [invalid, status, message];
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
  final String? reason;

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

/// What a kept backup holds.
enum SysBackupKind {
  full,
  link,
  preUpdate,
  preRestore;

  /// [linkId] names the link of a link backup.
  String label(String linkId) => switch (this) {
    full => S.current.bakKindFull,
    link => S.current.bakKindLink(linkId),
    preUpdate => S.current.bakKindPreUpdate,
    preRestore => S.current.bakKindPreRestore,
  };
}

/// Where the making of a kept backup is.
enum SysBackupState { pending, running, done, failed }

/// A kept backup as its row shows it.
final class SysBackupRow extends Equatable {
  const SysBackupRow({
    required this.id,
    required this.name,
    this.kind = SysBackupKind.full,
    this.link = '',
    this.sections = const [],
    this.created,
    this.state = SysBackupState.pending,
    this.progress = 0,
    this.sending = false,
    this.sendProgress = 0,
    this.size = 0,
  });

  final String id;
  final String name;
  final SysBackupKind kind;
  final String link;
  final List<String> sections;
  final DateTime? created;
  final SysBackupState state;

  /// Percent, while it is made and while it is sent.
  final int progress;
  final bool sending;
  final int sendProgress;

  /// Bytes.
  final int size;

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    link,
    sections,
    created,
    state,
    progress,
    sending,
    sendProgress,
    size,
  ];
}

/// The card *Backups*: the days a backup is kept, the kept ones.
final class SysBackupsData extends Equatable {
  const SysBackupsData({this.keepDays = 7, this.rows = const []});

  final int keepDays;
  final List<SysBackupRow> rows;

  @override
  List<Object?> get props => [keepDays, rows];
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
  final String? reason;

  /// `clear_conns` or a profile action runs.
  final bool busy;
  final List<SysStaleLink> stale;
  final List<SysProfile> profiles;

  /// The broker does not list its profiles: its answer.
  final String? profilesUnlisted;

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
  aclGrown,
  noStandby;

  /// Where it opens.
  String get go => switch (this) {
    standbyBehind || noStandby => S.current.sysAttnOpenAvail,
    linkFailed => S.current.sysAttnOpenLinks,
    quarantine => S.current.sysAttnOpenQuarantine,
    brokerWaiting => S.current.sysAttnOpenSites,
    aclGrown => S.current.sysAttnOpenAudit,
  };

  Tone get tone => switch (this) {
    linkFailed => Tone.bad,
    noStandby => Tone.neutral,
    standbyBehind || quarantine || brokerWaiting || aclGrown => Tone.warn,
  };
}

/// A card of the attention panel: what it is about, the subject (a link
/// id, a quarantine node), the certificate CN, the counts and since when.
final class SysAttentionData extends Equatable {
  const SysAttentionData(
    this.kind, {
    this.subject = '',
    this.name = '',
    this.count = 0,
    this.more = 0,
    this.since,
  });

  final SysAttention kind;
  final String subject;
  final String name;
  final int count;
  final int more;
  final DateTime? since;

  @override
  List<Object?> get props => [kind, subject, name, count, more, since];
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
