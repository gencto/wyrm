import 'package:app/mappers/notice_mappers.dart';
import 'package:app/mappers/system_mappers.dart';
import 'package:app/navigation/system_place.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';
import 'package:models/backup_status.dart';
import 'package:models/broker_self_update.dart';
import 'package:models/log_level.dart';
import 'package:models/log_read_error.dart';
import 'package:models/notice_kind.dart';
import 'package:models/self_update_state.dart';
import 'package:models/standby_state.dart';
import 'package:models/studio_notice.dart';
import 'package:models/sys_value.dart';
import 'package:models/system_notice.dart';
import 'package:models/system_tab.dart';
import 'package:models/traffic_measure.dart';
import 'package:models/withheld_args.dart';
import 'package:ui/pages/system_data.dart';

void main() {
  setUp(() => S.load(const Locale('en')));

  test('tabs, measures and levels go to ui and back unchanged', () {
    for (final t in SystemTab.values) {
      expect(t.sys.domain, t);
    }
    for (final m in TrafficMeasure.values) {
      expect(m.sys.domain, m);
    }
    for (final l in LogLevel.values) {
      expect(l.sys.domain, l);
      expect(l.sys.label, l.wire, reason: 'a level is shown by its name');
    }
  });

  test('a tile shows the sys value of its key, and leads where it fixes', () {
    for (final t in SysTileKey.values) {
      expect(t.place != null, t.opens, reason: '$t');
    }
    expect(SysTileKey.arbiterLease.value.key, 'arbiter_lease_s');
    expect(SysTileKey.aclDenied.place, SystemPlace.audit);
    expect(SysTileKey.quarantined.place, SystemPlace.quarantine);
    expect(SysValue.values.map((v) => v.key).toSet(), hasLength(25));
  });

  test('a failed log read: a refusal or an answer that is not a log', () {
    final refused = const LogReadError.refused('forbidden', 'needs config').sys;
    expect(refused, const SysLogRefused('forbidden', 'needs config'));
    expect(refused.text, 'forbidden: needs config');
    final invalid = const LogReadError.invalid('lines', 'not a list').sys;
    expect(invalid, const SysLogInvalid('lines', 'not a list'));
    expect(invalid.text, S.current.sysLogInvalid('lines: not a list'));
  });

  test('the standby: no value yet is no dot and no state', () {
    expect(StandbyState.unknown.sys, isNull);
    expect(StandbyState.none.sys?.dot, isNotNull);
    expect(StandbyState.following.sys?.dot, isNull);
  });

  test('a kept backup as its row: kind, state and sending', () {
    final row = const BackupJob(
      id: 'b4',
      kind: BackupKind.preRestore,
      status: BackupStatus.done,
      sendStatus: BackupSendStatus.sending,
      sendProgress: 30,
    ).row;
    expect(row.kind, const SysBackupPreRestore());
    expect(row.step, const SysBackupSending(30));
    expect(const BackupJob(id: 'b').row.step, const SysBackupKept());
    // a link backup names its link
    expect(
      const BackupJob(id: 'b', kind: BackupKind.link, link: 'plc').row.kind,
      const SysBackupOfLink('plc'),
    );
  });

  test('a kept backup says one step: made, failed, sent, else kept', () {
    SysBackupStep step(BackupStatus status, BackupSendStatus send) => BackupJob(
      id: 'b',
      status: status,
      progress: 40,
      sendStatus: send,
      sendProgress: 70,
    ).row.step;
    // being made wins over being sent, and so does a failure
    expect(
      step(BackupStatus.running, BackupSendStatus.sending),
      const SysBackupRunning(40),
    );
    expect(
      step(BackupStatus.failed, BackupSendStatus.sending),
      const SysBackupMakeFailed(),
    );
    // one not yet known to run is sent like one that is made
    expect(
      step(BackupStatus.unknown, BackupSendStatus.sending),
      const SysBackupSending(70),
    );
    for (final send in [
      BackupSendStatus.none,
      BackupSendStatus.done,
      BackupSendStatus.failed,
    ]) {
      expect(step(BackupStatus.done, send), const SysBackupKept());
      expect(step(BackupStatus.unknown, send), const SysBackupKept());
    }
  });

  test('the broker update as the card says it', () {
    expect(
      const BrokerSelfUpdate(version: '0.1.0', latest: '0.2.0').card,
      const SysVersionData(version: '0.1.0', latest: '0.2.0', newer: true),
    );
    expect(
      const BrokerSelfUpdate(
        version: '0.2.0',
        latest: '0.2.0',
        state: SelfUpdateState.staged,
      ).card,
      const SysVersionData(
        version: '0.2.0',
        latest: '0.2.0',
        state: SysSelfUpdate.trial,
        runs: true,
      ),
    );
  });

  test('every notice of System is worded as its toast was', () {
    String words(SystemNotice n) {
      final t = StudioNotice(id: 1, system: n).toast;
      return [t.title, if (t.line.isNotEmpty) t.line].join(' / ');
    }

    expect(
      words(const SystemNotice.profilePut('acme:ahu')),
      S.current.sysProfilePut('acme:ahu'),
    );
    expect(
      words(const SystemNotice.profileRemoved('acme:ahu')),
      S.current.sysProfileRemoved('acme:ahu'),
    );
    expect(
      words(const SystemNotice.commandCopied()),
      S.current.sysCommandCopied,
    );
    expect(
      words(const SystemNotice.guideCopied('https://x')),
      S.current.sysGuideCopied('https://x'),
    );
    expect(words(const SystemNotice.logCopied(2)), S.current.sysLogCopied(2));
    expect(
      words(const SystemNotice.logSaved('/tmp/a.log')),
      S.current.sysLogSaved('/tmp/a.log'),
    );
    expect(
      words(const SystemNotice.logNotSaved('no room')),
      '${S.current.sysLogNotSaved} / no room',
    );
    expect(
      words(SystemNotice.cleared(['a', 'b'].lock)),
      S.current.sysCleared('a, b'),
    );
    expect(
      words(const SystemNotice.cleared(IListConst([]))),
      S.current.sysClearedNone,
    );
    // a notice of another screen is worded by its kind
    final copied = const StudioNotice(
      id: 2,
      kind: NoticeKind.reportCopied,
    ).toast;
    expect(
      [copied.title, copied.line],
      [S.current.errCopied, S.current.errReportCopied],
    );
    final saved = StudioNotice(
      id: 3,
      kind: NoticeKind.planSaved,
      path: '/tmp/task-7.plan.json',
      leftOut: [
        WithheldArgs(step: 1, names: ['unit'].lock),
        WithheldArgs(step: 3, names: ['user', 'password'].lock),
      ].lock,
    ).toast;
    expect(
      saved.title,
      'Saved /tmp/task-7.plan.json. Run it with wyrm-agent run.',
    );
    expect(
      saved.line,
      'Secret arguments are not in the file: step 1: unit; '
      'step 3: user, password. Add them before you run it.',
    );
  });
}
