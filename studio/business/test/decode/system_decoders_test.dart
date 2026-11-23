import 'package:business/redux/app_state.dart';
import 'package:business/wyrm/decode/backup_job.dart';
import 'package:business/wyrm/decode/broker_self_update.dart';
import 'package:business/wyrm/decode/cleared_links.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/log_lines.dart';
import 'package:business/wyrm/decode/sys_about.dart';
import 'package:business/wyrm/decode/sys_status.dart';
import 'package:business/wyrm/decode/traffic_sample.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_kind.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_status.dart';
import 'package:models/backups_attrs.dart';
import 'package:models/broker_self_update.dart';
import 'package:models/live_value.dart';
import 'package:models/log_level.dart';
import 'package:models/log_line.dart';
import 'package:models/self_update_state.dart';
import 'package:models/send_link.dart';
import 'package:models/sys_value.dart';
import 'package:models/traffic_sample.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The decoders behind System (studio-rules §8): `sys` values, the kept
/// backups, `get_log`, `clear_conns`, a node's description, the broker's
/// own update and the traffic rates. Each shape decodes once, typed; a
/// value of another shape names its field, and a decoder that leaves a
/// value out logs why.
void main() {
  final warned = <String>[];
  setUpAll(() {
    Logger.root.level = Level.ALL;
    decodeLog.onRecord.listen((r) => warned.add(r.message));
  });
  setUp(warned.clear);

  /// The value of a [Valid]; fails the test for an [Invalid].
  T valid<T>(Decoded<T> d) => switch (d) {
    Valid(:final value) => value,
    final Invalid<T> i => fail('$i'),
  };

  group('sys values', () {
    test('decoded once per change of the live values, not per read', () {
      final values = IMap({
        'wy/plant/sys/links_connected': LiveValue(
          time: DateTime.utc(2026),
          value: 'four',
        ),
        'wy/plant/sys/sessions': LiveValue(time: DateTime.utc(2026), value: 7),
      });
      final a = AppState.initial();
      var state = a.copyWith(
        site: a.site.copyWith(name: 'plant'),
        live: a.live.copyWith(values: values),
      );
      // reads of every selector that needs it, and a change elsewhere
      for (var i = 0; i < 3; i++) {
        final s = _Sel(state);
        expect(s.sysStatus[SysValue.sessions], 7);
        expect(s.standby, isNotNull);
        expect(s.attention, isEmpty);
        state = state.copyWith.system(lines: 100 + i);
      }
      expect(warned, ['sys of plant: sys.links_connected: not a number']);
      // a tick of a point that is not of sys decodes nothing again
      state = state.copyWith.live(
        values: state.live.values.add(
          'wy/plant/downstream/modbus/plc1/t1/~val',
          LiveValue(time: DateTime.utc(2026), value: 21.5),
        ),
      );
      expect(_Sel(state).sysStatus[SysValue.sessions], 7);
      expect(warned, hasLength(1));
      // a new value of sys is decoded again
      state = state.copyWith.live(
        values: values.add(
          'wy/plant/sys/sessions',
          LiveValue(time: DateTime.utc(2026), value: 8),
        ),
      );
      expect(_Sel(state).sysStatus[SysValue.sessions], 8);
      expect(warned, hasLength(2));
    });

    test('numbers, texts, the start time and the level decode once', () {
      final values = <String, Object?>{
        'links_connected': 4,
        'cpu': 3.42,
        'history/database_size': 310,
        'version': '0.1.0',
        'zenoh_version': '1.10.1',
        'distribution': 'rust (prod)',
        'start_time': '2026-11-04T21:58:07Z',
        'uptime': 533000,
        'log_level': 2,
      };
      final s = sysStatusOf((k) => values[k], 'sys of plant');
      expect(s[SysValue.linksConnected], 4);
      expect(s[SysValue.cpu], 3.42);
      expect(s[SysValue.historySize], 310);
      expect(s[SysValue.sessions], isNull, reason: 'not arrived');
      expect(s.version, '0.1.0');
      expect(s.zenohVersion, '1.10.1');
      expect(s.distribution, 'rust (prod)');
      expect(s.startTime, DateTime.utc(2026, 11, 4, 21, 58, 7));
      expect(s.uptime, const Duration(days: 6, hours: 4, seconds: 200));
      expect(s.logLevel, LogLevel.info);
      expect(warned, isEmpty);
    });

    test('a value of another type is left out and logged; others stay', () {
      final values = <String, Object?>{
        'links_connected': '4',
        'sessions': 7,
        'start_time': 'yesterday',
        'version': 1,
      };
      final s = sysStatusOf((k) => values[k], 'sys of plant');
      expect(s[SysValue.linksConnected], isNull);
      expect(s[SysValue.sessions], 7);
      expect(s.startTime, isNull);
      expect(s.version, isNull);
      expect(warned, [
        'sys of plant: sys.links_connected: not a number',
        'sys of plant: sys.version: not a text',
        'sys of plant: sys.start_time: not an ISO 8601 time',
      ]);
    });

    test('log_level: a code (an int or a whole float) or a name', () {
      for (final l in LogLevel.values) {
        expect(logLevelOf(l.code), Valid<LogLevel?>(l));
        expect(logLevelOf(l.code.toDouble()), Valid<LogLevel?>(l));
        expect(logLevelOf(l.wire), Valid<LogLevel?>(l));
      }
      expect(logLevelOf(null), const Valid<LogLevel?>(null));
      expect(
        logLevelOf(9),
        const Invalid<LogLevel?>('sys', 'log_level', 'not a level code'),
      );
      expect(
        logLevelOf('loud'),
        const Invalid<LogLevel?>('sys', 'log_level', 'not a level name'),
      );
      expect(
        logLevelOf(true),
        const Invalid<LogLevel?>('sys', 'log_level', 'not a code or a name'),
      );
    });
  });

  group('kept backups', () {
    NodeMeta meta(Map<String, Value> attr) => NodeMeta(attr: attr);

    test('a meta decodes with its defaults', () {
      expect(
        backupJobOf('b1', meta({})),
        const Valid(BackupJob(id: 'b1', name: 'b1')),
      );
      expect(
        backupJobOf(
          'b2',
          meta({
            'kind': const VStr('pre-update'),
            'name': const VStr('plant-b2.wyrm-backup'),
            'sections': const VArray([VStr('control'), VStr('keys')]),
            'sealed': const VStr('passphrase'),
            'link': const VStr('modbus'),
            'by': const VStr('user:olena'),
          }),
        ),
        Valid(
          BackupJob(
            id: 'b2',
            kind: BackupKind.preUpdate,
            name: 'plant-b2.wyrm-backup',
            sections: [BackupSection.control, BackupSection.keys].lock,
            sealed: BackupSealed.passphrase,
            link: 'modbus',
            by: 'user:olena',
          ),
        ),
      );
    });

    test('an unknown kind or seal, or a field of another shape, names it', () {
      expect(
        backupJobOf('b', meta({'kind': const VStr('half')})),
        const Invalid<BackupJob>('backup', 'kind', 'not a kind'),
      );
      expect(
        backupJobOf('b', meta({'sealed': const VStr('wax')})),
        const Invalid<BackupJob>('backup', 'sealed', 'not a seal'),
      );
      expect(
        backupJobOf('b', meta({'name': const VInt(3)})),
        const Invalid<BackupJob>('backup', 'name', 'not a text'),
      );
      expect(
        backupJobOf(
          'b',
          meta({
            'sections': const VArray([VInt(1)]),
          }),
        ),
        const Invalid<BackupJob>('backup', 'sections', 'not texts'),
      );
      expect(
        backupJobOf('b', meta({'sections': const VStr('control')})),
        const Invalid<BackupJob>('backup', 'sections', 'not an array'),
      );
    });

    test('live values lay over the meta; one of another shape is kept', () {
      final values = <String, Object?>{
        'status': 'running',
        'progress': 40.0,
        'size': 'big',
        'created': '2026-11-12T01:00:00Z',
        'send_status': 'sending',
        'send_progress': 30,
      };
      final j = backupLiveOf(
        const BackupJob(id: 'b1', size: 812),
        (leaf) => values[leaf],
        'sys/backups/b1',
      );
      expect(j.status, BackupStatus.running);
      expect(j.progress, 40);
      expect(j.size, 812, reason: 'the old size stays');
      expect(j.created, DateTime.utc(2026, 11, 12, 1));
      expect(j.sendStatus, BackupSendStatus.sending);
      expect(j.sendProgress, 30);
      expect(warned, ['sys/backups/b1: backup.size: not a whole number']);
    });

    test('send_links: link and folder, the folder backups by default', () {
      expect(
        valid(
          sendLinksOf(
            Value.from([
              {'link': 's3', 'folder': 'kept'},
              {'link': 'drive'},
            ]),
          ),
        ),
        [
          const SendLink(link: 's3', folder: 'kept'),
          const SendLink(link: 'drive'),
        ],
      );
      expect(valid(sendLinksOf(null)), isEmpty);
      expect(
        sendLinksOf(
          Value.from([
            {'folder': 'kept'},
          ]),
        ),
        const Invalid<IList<SendLink>>('send links', 'link', 'missing'),
      );
      expect(
        sendLinksOf(const VStr('s3')),
        const Invalid<IList<SendLink>>('send links', '', 'not an array'),
      );
    });

    test('the attributes of sys/backups', () {
      final a = backupsAttrsOf(
        NodeMeta(
          attr: {
            'export_secrets': const VBool(true),
            'keep_days': const VInt(14),
            'sections': const VArray([VStr('control'), VStr('history')]),
            'send_links': Value.from([
              {'link': 's3'},
            ]),
          },
        ),
      );
      expect(a, isA<Valid<BackupsAttrs>>());
      final v = (a as Valid<BackupsAttrs>).value;
      expect(v.exportSecrets, isTrue);
      expect(v.keepDays, 14);
      expect(v.sections, [BackupSection.control, BackupSection.history]);
      expect(v.sendLinks, [const SendLink(link: 's3')]);
      expect(
        backupsAttrsOf(NodeMeta(attr: {'keep_days': const VStr('7')})),
        const Invalid<BackupsAttrs>(
          'backups',
          'keep_days',
          'not a whole number',
        ),
      );
    });
  });

  group('get_log', () {
    test('records of an array or a row each, a text as a message', () {
      final got = valid(
        logLinesOf([
          Value.from([
            {
              'time': '2026-11-12T02:01:40Z',
              'level': 'warn',
              'target': 'wyrm_admin',
              'message': 'link bacnet stopped',
            },
          ]),
          const VStr('a plain line'),
        ]),
      );
      expect(
        got,
        [
          LogLine(
            time: '2026-11-12T02:01:40Z',
            at: DateTime.utc(2026, 11, 12, 2, 1, 40),
            level: LogLevel.warn,
            target: 'wyrm_admin',
            message: 'link bacnet stopped',
          ),
          const LogLine(message: 'a plain line'),
        ],
      );
    });

    test('a level by name; none when the record names none', () {
      expect(
        valid(
          logLinesOf([
            Value.from({'level': 'debug', 'message': 'a'}),
            Value.from({'message': 'b'}),
          ]),
        ).map((l) => l.level),
        [LogLevel.debug, null],
      );
      expect(
        logLinesOf([
          Value.from({'level': 'loud', 'message': 'x'}),
        ]),
        const Invalid<List<LogLine>>('log line', 'level', 'not a level name'),
      );
    });

    test('a field that is not a text names it', () {
      expect(
        logLinesOf([
          Value.from({'time': 3, 'message': 'x'}),
        ]),
        const Invalid<List<LogLine>>('log line', 'time', 'not a text'),
      );
      expect(
        logLinesOf([const VInt(3)]),
        const Invalid<List<LogLine>>('log line', '', 'not a record'),
      );
    });
  });

  test('clear_conns: ids as arrays or texts, none as nothing', () {
    expect(
      valid(
        clearedLinksOf([
          const VArray([VStr('a'), VStr('b')]),
          const VStr('c'),
          const VNull(),
        ]),
      ),
      ['a', 'b', 'c'],
    );
    expect(valid(clearedLinksOf(const [])), isEmpty);
    expect(
      clearedLinksOf([
        const VArray([VInt(1)]),
      ]),
      const Invalid<List<String>>('cleared links', '', 'not a text id'),
    );
  });

  test('a node of sys: its description and unit', () {
    expect(
      sysAboutOf(
        NodeMeta(
          unit: const TText('%'),
          attr: {'description': const VStr('CPU of the broker')},
        ),
      ),
      const Valid<SysAbout>((description: 'CPU of the broker', unit: '%')),
    );
    expect(
      sysAboutOf(NodeMeta()),
      const Valid<SysAbout>((description: null, unit: null)),
    );
    expect(
      sysAboutOf(NodeMeta(attr: {'description': const VInt(1)})),
      const Invalid<SysAbout>('sys node', 'description', 'not a text'),
    );
  });

  group('the broker update', () {
    test('values, defaults, and update_last as texts', () {
      final values = <String, Object?>{
        'version': '0.1.0',
        'latest': '0.2.0',
        'update_state': 'rolled_back',
        'update_mode': '',
        'update_last': {'from': '0.1.0', 'to': '0.2.0', 'down_s': 9},
      };
      expect(
        brokerSelfUpdateOf((k) => values[k], 'update of plant'),
        const BrokerSelfUpdate(
          version: '0.1.0',
          latest: '0.2.0',
          state: SelfUpdateState.rolledBack,
          last: UpdateLast(from: '0.1.0', to: '0.2.0', downS: '9'),
        ),
      );
      expect(
        brokerSelfUpdateOf((_) => null, 'update of plant'),
        const BrokerSelfUpdate(),
      );
      expect(warned, isEmpty);
    });

    test('a state not known is left at none and logged', () {
      final u = brokerSelfUpdateOf(
        (k) => k == 'update_state' ? 'sideways' : null,
        'update of plant',
      );
      expect(u.state, SelfUpdateState.none);
      expect(warned, [
        'update of plant: sys.update_state: not a known name',
      ]);
    });

    test('update_last of another shape names it', () {
      expect(
        updateLastOf({'from': true}),
        const Invalid<UpdateLast>(
          'update_last',
          'from',
          'not a text or a number',
        ),
      );
      expect(
        updateLastOf('0.1.0'),
        const Invalid<UpdateLast>('sys', 'update_last', 'not a map'),
      );
    });
  });

  group('traffic rates', () {
    LiveValue at(int minute, Object? v) =>
        LiveValue(time: DateTime.utc(2026, 11, 12, 1, minute), value: v);
    List<(String, LiveValue?)> rates(List<LiveValue?> v) => [
      for (final (i, k) in const [
        'messages_in_per_second',
        'messages_out_per_second',
        'frames_in_per_second',
        'frames_out_per_second',
        'data_in_per_second',
        'data_out_per_second',
      ].indexed)
        (k, v[i]),
    ];

    test('six numbers at the newest of their times', () {
      expect(
        trafficSampleOf(
          rates([
            at(1, 10),
            at(2, 11),
            at(1, 3),
            at(1, 4),
            at(3, 5.5),
            at(1, 6),
          ]),
        ),
        Valid<TrafficSample?>(
          TrafficSample(
            time: DateTime.utc(2026, 11, 12, 1, 3),
            messagesIn: 10,
            messagesOut: 11,
            framesIn: 3,
            framesOut: 4,
            dataIn: 5.5,
            dataOut: 6,
          ),
        ),
      );
    });

    test('none while one has not arrived; another shape names its key', () {
      expect(
        trafficSampleOf(
          rates([at(1, 1), null, at(1, 1), at(1, 1), at(1, 1), at(1, 1)]),
        ),
        const Valid<TrafficSample?>(null),
      );
      expect(
        trafficSampleOf(
          rates([at(1, 1), at(1, 'x'), at(1, 1), at(1, 1), at(1, 1), at(1, 1)]),
        ),
        const Invalid<TrafficSample?>(
          'sys',
          'messages_out_per_second',
          'not a number',
        ),
      );
    });
  });
}

class _Sel with Selectors, NothingInFlight {
  _Sel(this.state);

  @override
  final AppState state;
}
