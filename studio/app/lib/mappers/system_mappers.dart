import 'package:business/redux/app_state.dart'
    show SelectBackups, TrafficTrendView;
import 'package:business/redux/last_result.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/attention_item.dart';
import 'package:models/attention_kind.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';
import 'package:models/backup_status.dart';
import 'package:models/backups_read.dart';
import 'package:models/broker_self_update.dart';
import 'package:models/link_info.dart';
import 'package:models/log_level.dart';
import 'package:models/log_line.dart';
import 'package:models/log_read_error.dart';
import 'package:models/self_update_state.dart';
import 'package:models/standby_state.dart';
import 'package:models/sys_status.dart';
import 'package:models/sys_value.dart';
import 'package:models/system_notice.dart';
import 'package:models/system_tab.dart';
import 'package:models/traffic_measure.dart';
import 'package:models/traffic_sample.dart';
import 'package:ui/alerts/system_toast.dart';
import 'package:ui/pages/system_data.dart';

import '../navigation/system_place.dart';
import 'backup_mappers.dart';

// System's domain as `ui` draws it (studio-rules §3): one exhaustive
// switch per enum, both ways where a control reports a `ui` value back. A
// new value on either side is a compile error here, not a silent default.

extension SystemTabSys on SystemTab {
  SysTab get sys => switch (this) {
    SystemTab.overview => SysTab.overview,
    SystemTab.availability => SysTab.availability,
    SystemTab.log => SysTab.log,
    SystemTab.maintenance => SysTab.maintenance,
  };
}

extension SysTabDomain on SysTab {
  SystemTab get domain => switch (this) {
    SysTab.overview => SystemTab.overview,
    SysTab.availability => SystemTab.availability,
    SysTab.log => SystemTab.log,
    SysTab.maintenance => SystemTab.maintenance,
  };
}

extension TrafficMeasureSys on TrafficMeasure {
  SysMeasure get sys => switch (this) {
    TrafficMeasure.messages => SysMeasure.messages,
    TrafficMeasure.frames => SysMeasure.frames,
    TrafficMeasure.bytes => SysMeasure.bytes,
  };
}

extension SysMeasureDomain on SysMeasure {
  TrafficMeasure get domain => switch (this) {
    SysMeasure.messages => TrafficMeasure.messages,
    SysMeasure.frames => TrafficMeasure.frames,
    SysMeasure.bytes => TrafficMeasure.bytes,
  };
}

extension LogLevelSys on LogLevel {
  SysLevel get sys => switch (this) {
    LogLevel.error => SysLevel.error,
    LogLevel.warn => SysLevel.warn,
    LogLevel.info => SysLevel.info,
    LogLevel.debug => SysLevel.debug,
    LogLevel.trace => SysLevel.trace,
  };
}

extension SysLevelDomain on SysLevel {
  LogLevel get domain => switch (this) {
    SysLevel.error => LogLevel.error,
    SysLevel.warn => LogLevel.warn,
    SysLevel.info => LogLevel.info,
    SysLevel.debug => LogLevel.debug,
    SysLevel.trace => LogLevel.trace,
  };
}

extension StandbyStateSys on StandbyState {
  /// Null before `standby_connected` arrived.
  SysStandby? get sys => switch (this) {
    StandbyState.unknown => null,
    StandbyState.none => SysStandby.none,
    StandbyState.following => SysStandby.following,
    StandbyState.behind => SysStandby.behind,
  };
}

extension SysTileKeyValue on SysTileKey {
  /// The value of `sys` the tile shows.
  SysValue get value => switch (this) {
    SysTileKey.linksConnected => SysValue.linksConnected,
    SysTileKey.quarantined => SysValue.quarantined,
    SysTileKey.packagesTotal => SysValue.packagesTotal,
    SysTileKey.upstreamConnected => SysValue.upstreamConnected,
    SysTileKey.downstreamConnected => SysValue.downstreamConnected,
    SysTileKey.sessions => SysValue.sessions,
    SysTileKey.cpu => SysValue.cpu,
    SysTileKey.memory => SysValue.memory,
    SysTileKey.diskFree => SysValue.diskFree,
    SysTileKey.dataSize => SysValue.dataSize,
    SysTileKey.aclDenied => SysValue.aclDenied,
    SysTileKey.auditRecords => SysValue.auditRecords,
    SysTileKey.standbyConnected => SysValue.standbyConnected,
    SysTileKey.standbyLag => SysValue.standbyLag,
    SysTileKey.arbiterLease => SysValue.arbiterLease,
    SysTileKey.standbyForks => SysValue.standbyForks,
  };

  /// Where the tile leads; null for a tile that is not a link.
  SystemPlace? get place => switch (this) {
    SysTileKey.linksConnected || SysTileKey.packagesTotal => SystemPlace.links,
    SysTileKey.quarantined => SystemPlace.quarantine,
    SysTileKey.upstreamConnected ||
    SysTileKey.downstreamConnected => SystemPlace.sites,
    SysTileKey.dataSize => SystemPlace.history,
    SysTileKey.aclDenied || SysTileKey.auditRecords => SystemPlace.audit,
    SysTileKey.sessions ||
    SysTileKey.cpu ||
    SysTileKey.memory ||
    SysTileKey.diskFree ||
    SysTileKey.standbyConnected ||
    SysTileKey.standbyLag ||
    SysTileKey.arbiterLease ||
    SysTileKey.standbyForks => null,
  };
}

extension SysElsewherePlace on SysElsewhere {
  SystemPlace get place => switch (this) {
    SysElsewhere.quarantine => SystemPlace.quarantine,
    SysElsewhere.sites => SystemPlace.sites,
    SysElsewhere.access => SystemPlace.access,
    SysElsewhere.history => SystemPlace.history,
    SysElsewhere.gallery => SystemPlace.gallery,
  };
}

extension AttentionKindSys on AttentionKind {
  SysAttention get sys => switch (this) {
    AttentionKind.standbyBehind => SysAttention.standbyBehind,
    AttentionKind.linkFailed => SysAttention.linkFailed,
    AttentionKind.quarantine => SysAttention.quarantine,
    AttentionKind.brokerWaiting => SysAttention.brokerWaiting,
    AttentionKind.waitingNotRead => SysAttention.waitingNotRead,
    AttentionKind.aclGrown => SysAttention.aclGrown,
    AttentionKind.noStandby => SysAttention.noStandby,
  };
}

extension AttentionItemSys on AttentionItem {
  SysAttentionData get sys => SysAttentionData(
    kind.sys,
    subject: subject,
    name: name,
    count: count,
    more: more,
    since: since,
  );
}

extension LogLineSys on LogLine {
  SysLogLine get sys => SysLogLine(
    time: time,
    at: at,
    level: level?.sys,
    target: target,
    message: message,
  );
}

extension TrafficSampleSys on TrafficSample {
  /// The rates of [measure] at this sample, unscaled.
  SysRate rateOf(TrafficMeasure measure) => SysRate(
    time.microsecondsSinceEpoch,
    rate(measure, inward: true),
    rate(measure, inward: false),
  );
}

/// The ring of [samples] as rates of [measure]: mapped again only when the
/// ring or the measure is another (up to one hour of samples, not on every
/// dispatch).
List<SysRate> sysRatesOf(
  IList<TrafficSample> samples,
  TrafficMeasure measure,
) => _rates.of(
  [samples, measure],
  () => [for (final s in samples) s.rateOf(measure)],
);

final _rates = LastResult<List<SysRate>>();

extension BackupKindSys on BackupKind {
  SysBackupKind get sys => switch (this) {
    BackupKind.full => SysBackupKind.full,
    BackupKind.link => SysBackupKind.link,
    BackupKind.preUpdate => SysBackupKind.preUpdate,
    BackupKind.preRestore => SysBackupKind.preRestore,
  };
}

extension BackupStatusSys on BackupStatus {
  SysBackupState get sys => switch (this) {
    BackupStatus.unknown => SysBackupState.pending,
    BackupStatus.running => SysBackupState.running,
    BackupStatus.done => SysBackupState.done,
    BackupStatus.failed => SysBackupState.failed,
  };
}

extension BackupSendStatusSys on BackupSendStatus {
  /// The backup is being sent to a file store now.
  bool get sending => switch (this) {
    BackupSendStatus.sending => true,
    BackupSendStatus.none ||
    BackupSendStatus.done ||
    BackupSendStatus.failed => false,
  };
}

extension BackupsReadCard on BackupsRead {
  /// The card *Backups* of System: none for a broker without
  /// `sys/backups` (or before the first read), a card that says it was
  /// not read or that the read failed, or the kept backups ([rows]) with
  /// those that could not be read ([unread]).
  SysBackupsData? card({
    required int keepDays,
    required List<BackupJob> rows,
    required IList<String> unread,
  }) => switch (this) {
    BackupsRead.absent || BackupsRead.unknown => null,
    BackupsRead.unreadable => const SysBackupsData(
      state: SysBackupsState.unreadable,
    ),
    BackupsRead.failed => const SysBackupsData(state: SysBackupsState.failed),
    BackupsRead.read => SysBackupsData(
      keepDays: keepDays,
      rows: [for (final j in rows) j.row],
      unread: unread.unlock,
    ),
  };
}

extension BackupsCard on SelectBackups {
  /// The card *Backups* of System from what is known of `sys/backups`,
  /// with the kept backups [rows].
  SysBackupsData? card(List<BackupJob> rows) =>
      availability.card(keepDays: keepDays, rows: rows, unread: unread);
}

extension StaleLink on LinkInfo {
  /// The link as *Clear connections* lists it.
  SysStaleLink get stale => SysStaleLink(id, cn: certificateCn);
}

extension BackupJobRow on BackupJob {
  SysBackupRow get row => SysBackupRow(
    id: id,
    name: name,
    kind: kind.sys,
    link: link,
    sections: [for (final s in sections) s.part],
    created: created,
    state: status.sys,
    progress: progress,
    sending: sendStatus.sending,
    sendProgress: sendProgress,
    size: size,
  );
}

extension SelfUpdateStateSys on SelfUpdateState {
  SysSelfUpdate get sys => switch (this) {
    SelfUpdateState.staged || SelfUpdateState.trial => SysSelfUpdate.trial,
    SelfUpdateState.rolledBack => SysSelfUpdate.rolledBack,
    SelfUpdateState.none || SelfUpdateState.confirmed => SysSelfUpdate.idle,
  };
}

extension BrokerSelfUpdateCard on BrokerSelfUpdate {
  SysVersionData get card => SysVersionData(
    version: version,
    latest: latest,
    state: state.sys,
    newer: newer,
    runs: state.runs,
  );
}

extension SystemNoticeToast on SystemNotice {
  SysToastVm get toast => switch (this) {
    ProfilePutNotice(:final name) => SysToastVm(
      SysToast.profilePut,
      subject: name,
    ),
    ProfileRemovedNotice(:final name) => SysToastVm(
      SysToast.profileRemoved,
      subject: name,
    ),
    CommandCopiedNotice() => const SysToastVm(SysToast.commandCopied),
    GuideCopiedNotice(:final url) => SysToastVm(
      SysToast.guideCopied,
      subject: url,
    ),
    LogCopiedNotice(:final lines) => SysToastVm(
      SysToast.logCopied,
      count: lines,
    ),
    LogSavedNotice(:final path) => SysToastVm(
      SysToast.logSaved,
      subject: path,
    ),
    LogNotSavedNotice(:final error) => SysToastVm(
      SysToast.logNotSaved,
      subject: error,
    ),
    ClearedNotice(:final ids) when ids.isEmpty => const SysToastVm(
      SysToast.clearedNone,
    ),
    ClearedNotice(:final ids) => SysToastVm(
      SysToast.cleared,
      items: ids.toList(),
    ),
  };
}

extension SysStatusBroker on SysStatus {
  /// Every tile's reading: its key, its value, the node's [unit] and
  /// description ([about]).
  IMap<SysTileKey, SysReading> readings({
    required String? Function(SysValue v) unit,
    required String Function(SysValue v) about,
  }) => {
    for (final t in SysTileKey.values)
      t: SysReading(
        key: t.value.key,
        value: this[t.value],
        unit: unit(t.value),
        about: about(t.value),
      ),
  }.lock;

  /// The broker's build and when it started.
  SysBroker get broker => SysBroker(
    version: version,
    zenohVersion: zenohVersion,
    distribution: distribution,
    started: startTime,
    uptime: uptime,
  );
}

extension TrafficTrendSys on TrafficTrendView {
  SysTrendWindow get sys => SysTrendWindow(
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    windowStart: windowStart,
    windowEnd: windowEnd,
    minWindow: minWindow,
    following: following,
  );
}

extension LogReadErrorSys on LogReadError {
  SysLogError get sys => switch (this) {
    LogRefused(:final status, :final message) => SysLogError.refused(
      status,
      message,
    ),
    LogInvalid(:final field, :final reason) => SysLogError.invalid(
      field,
      reason,
    ),
  };
}
