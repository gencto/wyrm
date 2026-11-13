import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/backups/actions/apply_restore_action.dart';
import 'package:business/redux/backups/actions/cancel_download_action.dart';
import 'package:business/redux/backups/actions/check_restore_action.dart';
import 'package:business/redux/backups/actions/close_backup_action.dart';
import 'package:business/redux/backups/actions/create_backup_action.dart';
import 'package:business/redux/backups/actions/download_backup_action.dart';
import 'package:business/redux/backups/actions/estimate_backup_action.dart';
import 'package:business/redux/backups/actions/open_backup_action.dart';
import 'package:business/redux/backups/actions/remove_backup_action.dart';
import 'package:business/redux/backups/actions/retrieve_backups_action.dart';
import 'package:business/redux/backups/actions/retrieve_send_connections_action.dart';
import 'package:business/redux/backups/actions/send_backup_action.dart';
import 'package:business/redux/backups/actions/set_backup_form_action.dart';
import 'package:business/redux/backups/actions/upload_restore_action.dart';
import 'package:business/redux/link_install/actions/check_package_action.dart';
import 'package:business/redux/link_install/actions/choose_install_source_action.dart';
import 'package:business/redux/link_install/actions/install_backup_action.dart';
import 'package:business/redux/link_install/actions/set_accept_rights_action.dart';
import 'package:business/redux/link_install/actions/set_name_action.dart';
import 'package:business/redux/link_install/actions/set_source_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/login/actions/log_in_action.dart';
import 'package:business/redux/login/actions/set_gateway_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/login/actions/set_user_action.dart';
import 'package:business/wyrm/mappers/backup_mapper.dart';
import 'package:business/wyrm/package_check.dart';
import 'package:business/wyrm/transfer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/backup_job.dart';
import 'package:models/install_source.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'support/fake_wyrm.dart';

const _b = 'wy/central/sys/backups';
const _secret = 'correct-horse-battery';

Uint8List _bytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) i % 251]);

/// Answers `download_part` of [data] from the offset and length asked for.
List<Value> Function(Value?) _serve(Uint8List data) => (args) {
  final offset = (args!['offset']! as VInt).v;
  final len = (args['len']! as VInt).v;
  final end = (offset + len).clamp(0, data.length);
  return [
    VMap({
      'data': VBytes(data.sublist(offset, end)),
      'offset': VInt(offset),
      'size': VInt(data.length),
      'eof': VBool(end == data.length),
    }),
  ];
};

Uint8List _linkBackup({String how = 'broker', String kind = 'link'}) {
  final a = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'wyrm_backup': 1,
          'kind': kind,
          'site': 'plant',
          'broker': '0.1.0',
          'created': '2026-11-13T15:40:00Z',
          'sealed': {'how': how},
          'link': {
            'id': 'modbus',
            'driver': 'pkg:modbus',
            'mode': 'process',
            'package': 'modbus',
            'version': '0.5.0',
          },
          'sections': [
            {'name': 'settings', 'files': <Object>[]},
            {'name': 'data', 'files': <Object>[]},
            {'name': 'package', 'files': <Object>[]},
          ],
        }),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(a));
}

/// ADR 0048 §3: backups, the transfer in parts, restore, and Add a link ▸
/// From backup, against a fake session.
void main() {
  late FakeWyrmApi api;
  late Store<AppState> s;

  setUp(() async {
    final login = FakeLogin();
    api = login.session.api;
    s = fakeStore(login: login);
    await s.dispatchAndWait(SetGatewayAction('http://g'));
    await s.dispatchAndWait(SetUserAction('admin'));
    await s.dispatchAndWait(SetPasswordAction('pw'));
    await s.dispatchAndWait(LogInAction());
    api
      ..metas[_b] = NodeMeta(
        attr: {
          'export_secrets': const VBool(true),
          'keep_days': const VInt(7),
          'sections': const VArray([
            VStr('control'),
            VStr('keys'),
            VStr('dataflows'),
            VStr('storage'),
            VStr('history'),
            VStr('links'),
            VStr('packages'),
            VStr('config'),
          ]),
          'send_links': const VArray([
            VMap({'link': VStr('files'), 'folder': VStr('site/backups')}),
          ]),
        },
      )
      ..children_[_b] = [Child('b1', NodeMeta())]
      ..metas['$_b/b1'] = NodeMeta(
        attr: {
          'kind': const VStr('full'),
          'name': const VStr('central-2026-11-13-1540.wyrm-backup'),
          'sections': const VArray([VStr('control'), VStr('storage')]),
          'sealed': const VStr('none'),
          'by': const VStr('user:admin'),
        },
      );
    await s.dispatchAndWait(RetrieveBackupsAction());
  });

  Iterable<Call> invokes(String action) =>
      api.calls.where((c) => c.op == 'invoke' && c.action == action);

  group('transfer in parts', () {
    test('an upload sends parts of the broker size, in order', () async {
      final data = _bytes(250);
      final sent = <int>[];
      api
        ..invokes['$_b ▸ restore_begin'] = [
          const VMap({
            'upload': VStr('u1'),
            'part_size': VInt(100),
            'max_part': VInt(160),
          }),
        ]
        ..invokes['$_b ▸ restore_part'] = [
          const VMap({'received': VInt(0)}),
        ];

      final id = await uploadParts(
        api,
        _b,
        size: data.length,
        read: (o, n) async => data.sublist(o, o + n),
        onProgress: sent.add,
      );

      expect(id, 'u1');
      expect(invokes('restore_begin').single.args!['size'], const VInt(250));
      final parts = invokes('restore_part').toList();
      expect(parts.map((c) => c.args!['offset']), const [
        VInt(0),
        VInt(100),
        VInt(200),
      ]);
      expect((parts.last.args!['data']! as VBytes).v.length, 50);
      expect(parts.every((c) => c.args!['upload'] == const VStr('u1')), isTrue);
      expect(sent, [100, 200, 250]);
    });

    test('a part is never above max_part', () async {
      api
        ..invokes['$_b ▸ restore_begin'] = [
          const VMap({
            'upload': VStr('u1'),
            'part_size': VInt(4096),
            'max_part': VInt(64),
          }),
        ]
        ..invokes['$_b ▸ restore_part'] = [const VMap({})];
      final data = _bytes(100);

      await uploadParts(
        api,
        _b,
        size: 100,
        read: (o, n) async => data.sublist(o, o + n),
      );

      expect(
        invokes('restore_part')
            .map((c) => (c.args!['data']! as VBytes).v.length),
        [64, 36],
      );
    });

    test('a cancelled or failed upload is dropped on the broker', () async {
      api
        ..invokes['$_b ▸ restore_begin'] = [
          const VMap({'upload': VStr('u1'), 'part_size': VInt(10)}),
        ]
        ..invokes['$_b ▸ restore_part'] = [const VMap({})]
        ..invokes['$_b ▸ restore_abort'] = [];
      final data = _bytes(40);
      var parts = 0;

      await expectLater(
        uploadParts(
          api,
          _b,
          size: 40,
          read: (o, n) async => data.sublist(o, o + n),
          cancelled: () => parts++ == 2,
        ),
        throwsA(isA<TransferCancelled>()),
      );

      expect(invokes('restore_part'), hasLength(2));
      expect(invokes('restore_abort').single.args!['upload'], const VStr('u1'));

      api.calls.clear();
      api.errors['$_b ▸ restore_part'] = WyrmException.of(
        Status.resourceExhausted,
        'no room',
      );
      await expectLater(
        uploadParts(
          api,
          _b,
          size: 40,
          read: (o, n) async => data.sublist(o, o + n),
        ),
        throwsA(anything),
      );
      expect(invokes('restore_abort'), hasLength(1));
    });

    test(
      'a download reads from 0 until eof, each part written in order',
      () async {
        final data = _bytes(250);
        api.answers['$_b/b1 ▸ download_part'] = _serve(data);
        final got = BytesBuilder();
        final progress = <(int, int)>[];

        final n = await downloadParts(
          api,
          '$_b/b1',
          part: 100,
          write: (p) async => got.add(p),
          onProgress: (done, size) => progress.add((done, size)),
        );

        expect(n, 250);
        expect(got.toBytes(), data);
        expect(progress, [(100, 250), (200, 250), (250, 250)]);
        expect(invokes('download_part').map((c) => c.args!['offset']), const [
          VInt(0),
          VInt(100),
          VInt(200),
        ]);
      },
    );

    test('by default a download asks for the 4 MiB the broker gives', () async {
      api.answers['$_b/b1 ▸ download_part'] = _serve(_bytes(10));
      await downloadParts(api, '$_b/b1', write: (_) async {});
      expect(invokes('download_part').single.args!['len'], const VInt(4 << 20));
    });
  });

  group('sys/backups', () {
    test('its attributes and the kept backups are read', () {
      final b = s.state.backups;
      expect(b.exportSecrets, isTrue);
      expect(b.keepDays, 7);
      expect(b.sections, hasLength(8));
      expect(b.sendLinks.single.link, 'files');
      expect(b.sendLinks.single.folder, 'site/backups');
      expect(b.view, ['b1']);
      expect(b.table['b1']!.name, endsWith('.wyrm-backup'));
      expect(b.table['b1']!.by, 'user:admin');
    });

    test(
      'a broker without sys/backups offers none and fails nothing',
      () async {
        api.metas.remove(_b);

        final status = await s.dispatchAndWait(RetrieveBackupsAction());

        expect(status.isCompletedOk, isTrue);
        expect(s.state.backups.sections, isEmpty);
        expect(s.state.backups.view, isEmpty);
      },
    );

    test('the values of a backup overlay its meta; times are ISO texts', () {
      final j = backupLive(
        const BackupJob(id: 'b1'),
        (leaf) => switch (leaf) {
          'status' => 'done',
          'progress' => 100,
          'size' => 4096,
          'created' => '2026-11-13T15:40:12Z',
          'expires' => '2026-11-20T15:40:12Z',
          'send_status' => 'sending',
          'send_progress' => 40,
          _ => null,
        },
      );
      expect(j.status, 'done');
      expect(j.size, 4096);
      expect(j.created, '2026-11-13T15:40:12Z');
      expect(j.expires, '2026-11-20T15:40:12Z');
      expect(j.sendProgress, 40);
    });

    test('a broker backup starts with every section but keys', () {
      s.dispatchSync(OpenBackupAction());
      expect(s.state.backups.stage, 'choose');
      expect(s.state.backups.chosen.contains('keys'), isFalse);
      expect(s.state.backups.chosen.contains('history'), isTrue);
      expect(s.state.backups.historyDays, 30);
    });

    test(
      'estimate asks for every section with the range and the links',
      () async {
        api.invokes['$_b ▸ estimate'] = [
          const VMap({
            'sections': VMap({'control': VInt(1200), 'history': VInt(5000)}),
            'total': VInt(6200),
          }),
        ];
        s
          ..dispatchSync(OpenBackupAction())
          ..dispatchSync(SetBackupFormAction(historyDays: 7));

        await s.dispatchAndWait(EstimateBackupAction());

        final args = invokes('estimate').single.args!;
        expect((args['sections']! as VArray).v, hasLength(8));
        expect(args['history_days'], const VInt(7));
        expect(args['passphrase'], isNull);
        expect(s.state.backups.estimate['history'], 5000);
      },
    );

    test(
      'create sends what is ticked; the passphrase is in no state',
      () async {
        api.invokes['$_b ▸ create'] = [
          const VMap({'id': VStr('b2')}),
        ];
        s
          ..dispatchSync(OpenBackupAction())
          ..dispatchSync(SetBackupFormAction(toggle: 'keys'))
          ..dispatchSync(SetBackupFormAction(toggle: 'history'))
          ..dispatchSync(SetBackupFormAction(toggle: 'packages'))
          // `control` cannot be unticked.
          ..dispatchSync(SetBackupFormAction(toggle: 'control'));

        await s.dispatchAndWait(CreateBackupAction(passphrase: _secret));

        final args = invokes('create').single.args!;
        expect(
          [for (final v in (args['sections']! as VArray).v) (v as VStr).v],
          ['control', 'keys', 'dataflows', 'storage', 'links', 'config'],
        );
        expect(args['passphrase'], const VStr(_secret));
        expect(args['history_days'], isNull);
        expect(args['links'], isNull);
        expect(s.state.backups.stage, 'job');
        expect(s.state.backups.job, 'b2');
        expect('${s.state}', isNot(contains(_secret)));
      },
    );

    test('unticked links are named by the ones that stay', () async {
      api
        ..children_['wy/central/sys/links'] = [
          Child('modbus', NodeMeta()),
          Child('s7', NodeMeta()),
        ]
        ..metas['wy/central/sys/links/modbus'] = NodeMeta()
        ..metas['wy/central/sys/links/s7'] = NodeMeta()
        ..invokes['$_b ▸ create'] = [
          const VMap({'id': VStr('b2')}),
        ];
      await s.dispatchAndWait(RetrieveLinksAction());
      s
        ..dispatchSync(OpenBackupAction())
        ..dispatchSync(SetBackupFormAction(toggleLink: 's7'));

      await s.dispatchAndWait(CreateBackupAction());

      final args = invokes('create').single.args!;
      expect(args['links'], const VArray([VStr('modbus')]));
      expect(args['passphrase'], isNull);
    });

    test('a link backup calls the link with its sections', () async {
      const key = 'wy/central/sys/links/modbus';
      api.invokes['$key ▸ backup'] = [
        const VMap({'id': VStr('b3')}),
      ];
      s
        ..dispatchSync(OpenBackupAction(link: 'modbus'))
        ..dispatchSync(SetBackupFormAction(toggle: 'history'))
        ..dispatchSync(SetBackupFormAction(historyDays: 7));

      await s.dispatchAndWait(CreateBackupAction());

      final call = invokes('backup').single;
      expect(call.key, key);
      expect(
        [for (final v in (call.args!['sections']! as VArray).v) (v as VStr).v],
        ['settings', 'data', 'history'],
      );
      expect(call.args!['history_days'], const VInt(7));
      expect(s.state.backups.job, 'b3');
    });

    test('the package goes in only for a link that runs one', () async {
      api
        ..children_['wy/central/sys/links'] = [
          Child('mock', NodeMeta()),
          Child('avg', NodeMeta()),
        ]
        ..metas['wy/central/sys/links/mock'] = NodeMeta(
          attr: {'driver': const VStr('mock')},
        )
        ..metas['wy/central/sys/links/avg'] = NodeMeta(
          attr: {'driver': const VStr('pkg:average')},
        );
      await s.dispatchAndWait(RetrieveLinksAction());

      s.dispatchSync(OpenBackupAction(link: 'mock'));
      expect(s.state.backups.chosen.unlock, {'settings', 'data'});
      s.dispatchSync(OpenBackupAction(link: 'avg'));
      expect(s.state.backups.chosen.unlock, {'settings', 'data', 'package'});
    });

    test('a refused backup fails the action and keeps the dialog', () async {
      api.errors['$_b ▸ create'] = WyrmException.of(
        Status.permissionDenied,
        'passphrase: backups.export_secrets is false',
      );
      s.dispatchSync(OpenBackupAction());

      final status = await s.dispatchAndWait(
        CreateBackupAction(passphrase: _secret),
      );

      expect(status.isCompletedFailed, isTrue);
      expect(s.state.backups.stage, 'choose');
      // The refusal names the option, never the passphrase.
      expect('${status.originalError}', isNot(contains(_secret)));
    });

    test('a download writes every part and checks the SHA-256', () async {
      final data = _bytes(250);
      api.answers['$_b/b1 ▸ download_part'] = _serve(data);
      final got = BytesBuilder();
      var closed = false;

      final status = await s.dispatchAndWait(
        DownloadBackupAction(
          'b1',
          part: 100,
          path: '/tmp/b1.wyrm-backup',
          sha256: sha256.convert(data).toString(),
          write: (p) async => got.add(p),
          onDone: () async => closed = true,
        ),
      );

      expect(status.isCompletedOk, isTrue);
      expect(got.toBytes(), data);
      expect(closed, isTrue);
      expect(s.state.backups.downloading, isNull);
      expect(s.state.backups.downloaded, 250);
      expect(s.state.backups.savedTo, '/tmp/b1.wyrm-backup');
    });

    test('another dialog does not show the last download as its own', () async {
      api.answers['$_b/b1 ▸ download_part'] = _serve(_bytes(10));
      await s.dispatchAndWait(
        DownloadBackupAction('b1', path: '/tmp/b1', write: (_) async {}),
      );
      expect(s.state.backups.savedTo, '/tmp/b1');

      s.dispatchSync(OpenBackupAction(job: 'b1'));

      expect(s.state.backups.savedTo, isNull);
      expect(s.state.backups.downloaded, 0);
    });

    test('a file that is not the backup is an error and is removed', () async {
      api.answers['$_b/b1 ▸ download_part'] = _serve(_bytes(50));
      var removed = false;

      final status = await s.dispatchAndWait(
        DownloadBackupAction(
          'b1',
          path: '/tmp/x',
          sha256: 'ab' * 32,
          write: (_) async {},
          onCancel: () async => removed = true,
        ),
      );

      expect(status.isCompletedFailed, isTrue);
      expect(removed, isTrue);
      expect(s.state.backups.savedTo, isNull);
    });

    test('Cancel stops a download before its next part', () async {
      final data = _bytes(300);
      api.answers['$_b/b1 ▸ download_part'] = _serve(data);
      var removed = false;
      var parts = 0;

      final status = await s.dispatchAndWait(
        DownloadBackupAction(
          'b1',
          part: 100,
          path: '/tmp/x',
          write: (_) async {
            if (++parts == 1) {
              s.dispatchSync(CancelDownloadAction());
            }
          },
          onCancel: () async => removed = true,
        ),
      );

      expect(status.isCompletedOk, isTrue);
      expect(parts, 1);
      expect(removed, isTrue);
      expect(s.state.backups.savedTo, isNull);
    });

    test('remove and send call the backup', () async {
      api
        ..invokes['$_b/b1 ▸ remove'] = []
        ..invokes['$_b/b1 ▸ send'] = [
          const VMap({'to': VStr('files/s3/files/site/backups/x')}),
        ]
        ..children_['wy/central/downstream/files'] = [
          Child('s3', NodeMeta()),
          Child('status', NodeMeta()..ty = TypeCode.string),
        ];
      s
        ..dispatchSync(OpenBackupAction(job: 'b1'))
        ..dispatchSync(SetBackupFormAction(where: 'store', sendLink: 'files'));
      await s.dispatchAndWait(RetrieveSendConnectionsAction('files'));

      // The one connection of the link is the choice; a value is none.
      expect(s.state.backups.connections, ['s3']);
      expect(s.state.backups.sendConnection, 's3');

      s.dispatchSync(SetBackupFormAction(sendPath: ' nightly.wyrm-backup '));
      await s.dispatchAndWait(SendBackupAction('b1'));
      final args = invokes('send').single.args!;
      expect(args['link'], const VStr('files'));
      expect(args['connection'], const VStr('s3'));
      expect(args['path'], const VStr('nightly.wyrm-backup'));

      await s.dispatchAndWait(RemoveBackupAction('b1'));
      expect(invokes('remove').single.key, '$_b/b1');
    });
  });

  group('restore', () {
    Future<void> uploaded() async {
      api
        ..invokes['$_b ▸ restore_begin'] = [
          const VMap({'upload': VStr('u9'), 'part_size': VInt(64)}),
        ]
        ..invokes['$_b ▸ restore_part'] = [const VMap({})]
        ..invokes['$_b ▸ restore_abort'] = [];
      final data = _bytes(100);
      s.dispatchSync(OpenBackupAction(restore: true));
      await s.dispatchAndWait(
        UploadRestoreAction(
          name: 'plant.wyrm-backup',
          size: 100,
          read: (o, n) async => data.sublist(o, o + n),
        ),
      );
    }

    const check = VMap({
      'site': VStr('central'),
      'same_site': VBool(true),
      'created': VStr('2026-11-01T03:00:00Z'),
      'broker': VStr('0.1.0'),
      'sealed': VStr('passphrase'),
      'schemas': VMap({
        'registry': VMap({'backup': VInt(19), 'here': VInt(19)}),
      }),
      'sections': VMap({
        'control': VInt(1200),
        'keys': VInt(48),
        'history': VInt(9000),
        'links': VInt(300),
        'storage': VInt(20),
        'config': VInt(6),
      }),
      'keys': VStr('differ'),
      'keys_differ': VArray([VStr('secrets.bin')]),
      'control_opens_here': VBool(true),
      'links': VMap({'modbus': VStr('exists'), 'new1': VStr('new')}),
      'problems': VArray([]),
      'notes': VArray([VStr('a note')]),
    });

    test('the file goes up in parts and the check is read', () async {
      await uploaded();
      expect(s.state.backups.upload, 'u9');
      expect(s.state.backups.uploaded, 100);
      expect(s.state.backups.uploadName, 'plant.wyrm-backup');

      api.invokes['$_b ▸ restore_check'] = [check];
      await s.dispatchAndWait(CheckRestoreAction(passphrase: _secret));

      final args = invokes('restore_check').single.args!;
      expect(args['upload'], const VStr('u9'));
      expect(args['passphrase'], const VStr(_secret));
      final c = s.state.backups.check!;
      expect(c.sameSite, isTrue);
      expect(c.keys, 'differ');
      expect(c.keysDiffer, ['secrets.bin']);
      expect(c.schemas['registry'], (19, 19));
      expect(c.links['modbus'], 'exists');
      expect(c.notes, ['a note']);
      // History, keys and config are not ticked by themselves.
      expect(s.state.backups.chosen.unlock, {'control', 'links', 'storage'});
      expect('${s.state}', isNot(contains(_secret)));
    });

    test('add sends only what add takes and reports what it did', () async {
      await uploaded();
      api
        ..invokes['$_b ▸ restore_check'] = [check]
        ..invokes['$_b ▸ restore_apply'] = [
          const VMap({
            'done': VArray([VStr('link new1')]),
            'skipped': VArray([VStr('link modbus: exists')]),
            'restart': VBool(false),
          }),
        ];
      await s.dispatchAndWait(CheckRestoreAction());
      s.dispatchSync(SetBackupFormAction(acceptRights: true));

      await s.dispatchAndWait(ApplyRestoreAction());

      final args = invokes('restore_apply').single.args!;
      expect(args['mode'], const VStr('add'));
      expect(args['sections'], const VArray([VStr('links'), VStr('storage')]));
      expect(args['accept'], const VBool(true));
      expect(args['replace_keys'], isNull);
      expect(s.state.backups.stage, 'restored');
      expect(s.state.backups.result, contains('link new1'));
      expect(s.state.backups.result, contains('modbus: exists'));
    });

    test('replace with the keys restarts the broker', () async {
      await uploaded();
      api
        ..invokes['$_b ▸ restore_check'] = [check]
        ..invokes['$_b ▸ restore_apply'] = [
          const VMap({
            'sections': VArray([VStr('control'), VStr('keys')]),
            'restart': VBool(true),
          }),
        ];
      await s.dispatchAndWait(CheckRestoreAction(passphrase: _secret));
      s
        ..dispatchSync(SetBackupFormAction(mode: 'replace'))
        ..dispatchSync(SetBackupFormAction(toggle: 'keys'))
        ..dispatchSync(SetBackupFormAction(toggle: 'links'))
        ..dispatchSync(SetBackupFormAction(toggle: 'storage'))
        ..dispatchSync(SetBackupFormAction(replaceKeys: true));

      await s.dispatchAndWait(ApplyRestoreAction(passphrase: _secret));

      final args = invokes('restore_apply').single.args!;
      expect(args['mode'], const VStr('replace'));
      expect(args['sections'], const VArray([VStr('control'), VStr('keys')]));
      expect(args['replace_keys'], const VBool(true));
      expect(args['passphrase'], const VStr(_secret));
      expect(s.state.backups.stage, 'restarting');

      // An applied upload is the broker's: closing does not abort it.
      await s.dispatchAndWait(CloseBackupAction());
      expect(invokes('restore_abort'), isEmpty);
      expect(s.state.backups.stage, isNull);
    });

    test('closing before the restore drops the upload', () async {
      await uploaded();

      await s.dispatchAndWait(CloseBackupAction());

      expect(invokes('restore_abort').single.args!['upload'], const VStr('u9'));
      expect(s.state.backups.upload, isNull);
    });
  });

  group('Add a link ▸ From backup', () {
    test('the manifest of a link backup is read here', () {
      final r = checkBackup(_linkBackup());
      expect(r.checks.where((c) => c.result == 'failed'), isEmpty);
      expect(r.name, 'modbus');
      expect(r.kind, 'process');
      expect(
        r.checks.firstWhere((c) => c.title == 'Secrets').detail,
        contains('opens only on a broker'),
      );
      expect(r.manifest, contains('"kind": "link"'));
    });

    test('a broker backup and a file that is no zip fail the check', () {
      expect(
        checkBackup(_linkBackup(kind: 'full')).checks.last.result,
        'failed',
      );
      expect(
        checkBackup(Uint8List.fromList([1, 2, 3])).checks.single.result,
        'failed',
      );
    });

    Future<void> picked() async {
      s
        ..dispatchSync(ChooseInstallSourceAction('backup'))
        ..dispatchSync(
          SetSourceAction(
            InstallSource.backup(
              bytes: _linkBackup(how: 'passphrase'),
              fileName: 'modbus.wyrm-link',
            ),
          ),
        );
      await s.dispatchAndWait(CheckPackageAction());
    }

    test('the check names the link and its mode', () async {
      await picked();
      expect(s.state.linkInstall.name, 'modbus');
      expect(s.state.linkInstall.mode, LinkMode.process);
    });

    test('the file goes up in parts, then install_backup', () async {
      await picked();
      api
        ..invokes['$_b ▸ restore_begin'] = [
          const VMap({'upload': VStr('u5'), 'part_size': VInt(128)}),
        ]
        ..invokes['$_b ▸ restore_part'] = [const VMap({})]
        ..invokes['wy/central/sys/links ▸ install_backup'] = [
          const VMap({
            'success': VBool(true),
            'message': VStr('link modbus2 installed'),
          }),
        ]
        ..children_['wy/central/sys/links'] = [];
      s
        ..dispatchSync(SetNameAction('modbus2'))
        ..dispatchSync(SetAcceptRightsAction(true));

      await s.dispatchAndWait(InstallBackupAction(passphrase: _secret));

      expect(invokes('restore_part').length, greaterThan(1));
      final args = invokes('install_backup').single.args!;
      expect(args['upload'], const VStr('u5'));
      expect(args['id'], const VStr('modbus2'));
      expect(args['accept'], const VBool(true));
      expect(args['passphrase'], const VStr(_secret));
      expect(s.state.linkInstall.phase, 'done');
      expect(s.state.linkInstall.message, 'link modbus2 installed');
      expect('${s.state}', isNot(contains(_secret)));
    });

    test(
      'without accept the broker lists the rights and installs nothing',
      () async {
        await picked();
        api
          ..invokes['$_b ▸ restore_begin'] = [
            const VMap({'upload': VStr('u5')}),
          ]
          ..invokes['$_b ▸ restore_part'] = [const VMap({})]
          ..invokes['wy/central/sys/links ▸ install_backup'] = [
            const VMap({
              'success': VBool(false),
              'message': VStr('modbus asks for: net 10.0.4.0/24'),
            }),
          ];

        await s.dispatchAndWait(InstallBackupAction());

        expect(invokes('install_backup').single.args!['accept'], isNull);
        expect(invokes('install_backup').single.args!['passphrase'], isNull);
        expect(s.state.linkInstall.phase, 'failed');
        expect(s.state.linkInstall.message, contains('10.0.4.0/24'));
      },
    );

    test('a refused upload fails the install with the broker words', () async {
      await picked();
      api.errors['$_b ▸ restore_begin'] = WyrmException.of(
        Status.busy,
        'two uploads are open',
      );

      await s.dispatchAndWait(InstallBackupAction());

      expect(s.state.linkInstall.phase, 'failed');
      expect(s.state.linkInstall.message, contains('two uploads are open'));
    });
  });
}
