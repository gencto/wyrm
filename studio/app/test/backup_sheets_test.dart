import 'package:app/common/backup_sheets.dart';
import 'package:app/common/files.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/backup_job.dart';
import 'package:models/restore_check.dart';
import 'package:models/send_link.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/task_sheet.dart';

const _sections = [
  'control',
  'keys',
  'dataflows',
  'storage',
  'history',
  'links',
  'packages',
  'config',
];

BackupFormData _form({
  Set<String> chosen = const {'control', 'keys', 'storage'},
  bool exportSecrets = true,
  bool viaUpstream = false,
  int passphrase = 0,
  String where = 'computer',
  List<SendLink> sendLinks = const [],
  String? sendConnection,
  String? link,
  String? reason,
}) => BackupFormData(
  site: 'plant',
  link: link,
  sections: link == null ? _sections : const ['settings', 'data', 'package'],
  chosen: chosen,
  estimate: const {'control': 1200, 'keys': 48, 'storage': 2000},
  linkIds: const ['modbus', 's7'],
  exportSecrets: exportSecrets,
  viaUpstream: viaUpstream,
  passphraseLength: passphrase,
  where: where,
  sendLinks: sendLinks,
  sendLink: sendLinks.isEmpty ? null : sendLinks.first.link,
  connections: const ['s3'],
  sendConnection: sendConnection,
  reason: reason,
);

BackupJob _job({
  String status = 'done',
  List<String> sections = const ['control', 'storage'],
  String sealed = 'none',
  String sendStatus = '',
}) => BackupJob(
  id: 'b1',
  name: 'plant-2026-11-13-1540.wyrm-backup',
  sections: sections.lock,
  sealed: sealed,
  status: status,
  progress: status == 'done' ? 100 : 46,
  step: 'storage',
  size: 4096,
  sha256: 'ab' * 32,
  expires: '2026-11-20T15:40:12Z',
  error: status == 'failed' ? 'no room on the disk' : '',
  sendStatus: sendStatus,
  sendProgress: 40,
  sentTo: 'files/s3/files/backups/x',
  sendError: 'the name exists',
);

RestoreCheck _check({
  String keys = 'same',
  bool sameSite = true,
  List<String> problems = const [],
}) => RestoreCheck(
  site: sameSite ? 'plant' : 'other',
  sameSite: sameSite,
  broker: '0.1.0',
  sealed: 'passphrase',
  sections: const {
    'control': 1200,
    'keys': 48,
    'history': 9000,
    'links': 300,
    'storage': 20,
    'config': 6,
  }.lock,
  keys: keys,
  keysDiffer: [if (keys == 'differ') 'secrets.bin'].lock,
  links: const {'modbus': 'exists', 'new1': 'new'}.lock,
  problems: problems.lock,
);

RestoreData _restore({
  RestoreCheck? check,
  Set<String> chosen = const {'control', 'links', 'storage'},
  String mode = 'add',
  bool exportSecrets = true,
  bool viaUpstream = false,
  int passphrase = 0,
  bool replaceKeys = false,
}) => RestoreData(
  site: 'plant',
  fileName: 'plant.wyrm-backup',
  size: 100,
  uploaded: 100,
  hasUpload: true,
  check: check,
  chosen: chosen,
  mode: mode,
  exportSecrets: exportSecrets,
  viaUpstream: viaUpstream,
  passphraseLength: passphrase,
  replaceKeys: replaceKeys,
);

SheetSection _section(TaskSheetVm vm, String id) =>
    vm.blocks.whereType<SheetSection>().firstWhere((s) => s.id == id);

SheetChoice _choice(TaskSheetVm vm, String id) =>
    vm.blocks.whereType<SheetChoice>().firstWhere((c) => c.id == id);

/// The states of the backup dialogs (boards `Backup*`, `LinkBackup`, spec
/// `updates-backups.md` §2, §4).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  group('Back up', () {
    test('keys go in only with a passphrase the broker takes', () {
      final none = _form();
      expect(none.withKeys, isFalse);
      expect(none.sent, {'control', 'storage'});
      final keys = _section(backupFormSheet(none), 'keys');
      expect(keys.on, isFalse);
      expect(keys.locked, isTrue);
      expect(keys.reason, contains('12 characters'));

      final short = backupFormSheet(_form(passphrase: 5));
      expect(short.primaryEnabled, isFalse);
      expect(
        short.blocks.whereType<SheetField>().single.error,
        'At least 12 characters',
      );

      final ok = _form(passphrase: 14);
      expect(ok.withKeys, isTrue);
      expect(_section(backupFormSheet(ok), 'keys').on, isTrue);
      expect(backupFormSheet(ok).primaryEnabled, isTrue);
    });

    test('export_secrets false locks keys and the passphrase with it', () {
      final d = _form(exportSecrets: false, passphrase: 14);
      final vm = backupFormSheet(d);
      expect(d.withKeys, isFalse);
      expect(_section(vm, 'keys').locked, isTrue);
      expect(_section(vm, 'keys').reason, contains('export_secrets'));
      final field = vm.blocks.whereType<SheetField>().single;
      expect(field.enabled, isFalse);
      expect(field.note, contains('export_secrets'));
      // Everything else still works.
      expect(vm.primaryEnabled, isTrue);
    });

    test('a session through an upstream never gets keys or a passphrase', () {
      final d = _form(viaUpstream: true, passphrase: 14);
      final vm = backupFormSheet(d);
      expect(d.withKeys, isFalse);
      expect(_section(vm, 'keys').reason, contains('upstream'));
      expect(vm.blocks.whereType<SheetField>().single.enabled, isFalse);
    });

    test('the total is of what goes in; control is always in', () {
      final vm = backupFormSheet(_form(chosen: const {'storage'}));
      expect(_section(vm, 'control').on, isTrue);
      expect(_section(vm, 'control').locked, isTrue);
      expect(vm.note, startsWith('About 2.0 KiB'));
      expect(_section(vm, 'storage').size, '2.0 KiB');
    });

    test('a file store is offered only when the host lists one', () {
      final none = backupFormSheet(_form());
      expect(_choice(none, 'where').reasons['store'], contains('send_links'));

      const links = [SendLink(link: 'files', folder: 'site/backups')];
      final pick = backupFormSheet(_form(where: 'store', sendLinks: links));
      expect(_choice(pick, 'where').reasons, isEmpty);
      // No connection yet: the primary waits for one.
      expect(pick.primaryEnabled, isFalse);

      final ready = backupFormSheet(
        _form(where: 'store', sendLinks: links, sendConnection: 's3'),
      );
      expect(ready.primaryEnabled, isTrue);
      expect(
        ready.blocks
            .whereType<SheetFacts>()
            .expand((f) => f.facts)
            .map((f) => f.value),
        contains('s3/files/site/backups/'),
      );

      // A backup with the keys is never sent.
      final keys = backupFormSheet(
        _form(where: 'store', sendLinks: links, passphrase: 14),
      );
      expect(_choice(keys, 'where').reasons['store'], contains('never sent'));
    });

    test('without config the dialog is locked with the reason', () {
      final vm = backupFormSheet(_form(reason: 'needs config on sys/backups'));
      expect(vm.primaryEnabled, isFalse);
      expect(vm.primaryReason, 'needs config on sys/backups');
    });

    test('a link backup says how its private data is sealed', () {
      final site = backupFormSheet(
        _form(link: 'modbus', chosen: const {'data'}),
      );
      expect(site.title, 'Back up the link modbus');
      expect(_section(site, 'data').tag, 'sealed for this site');
      expect(_section(site, 'settings').locked, isTrue);
      expect(site.primary, 'Back up modbus');

      final sealed = backupFormSheet(
        _form(link: 'modbus', chosen: const {'data'}, passphrase: 14),
      );
      expect(_section(sealed, 'data').tag, 'passphrase');
      expect(_section(sealed, 'data').tagTone, Tone.warn);
    });
  });

  group('a backup job', () {
    test('running: the bar, the sections as steps, nothing to press', () {
      final vm = backupJobSheet(
        BackupJobData(
          job: _job(status: 'running'),
          site: 'plant',
        ),
      );
      expect(vm.blocks.whereType<SheetBar>().single.percent, 46);
      expect(
        vm.blocks.whereType<SheetSteps>().single.steps.map((s) => s.state),
        [SheetStepState.done, SheetStepState.now],
      );
      expect(vm.primaryEnabled, isFalse);
    });

    test('failed: the broker error and Remove', () {
      final d = BackupJobData(
        job: _job(status: 'failed'),
        site: 'plant',
      );
      final vm = backupJobSheet(d);
      expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.bad);
      expect(
        vm.blocks.whereType<SheetBanner>().single.text,
        'no room on the disk',
      );
      expect(d.primary, 'remove');
    });

    test('done: download, then show; cancel while it runs', () {
      final done = BackupJobData(job: _job(), site: 'plant');
      expect(done.primary, 'download');
      expect(backupJobSheet(done).primary, 'Download…');

      final running = BackupJobData(
        job: _job(),
        site: 'plant',
        downloading: true,
        downloaded: 1024,
      );
      expect(running.primary, 'cancel');
      expect(
        backupJobSheet(running).blocks.whereType<SheetBar>().single.percent,
        25,
      );

      final saved = BackupJobData(
        job: _job(),
        site: 'plant',
        savedTo: '/tmp/x.wyrm-backup',
      );
      expect(saved.primary, 'show');
      expect(
        backupJobSheet(saved).blocks.whereType<SheetText>().map((t) => t.text),
        contains(contains('/tmp/x.wyrm-backup')),
      );
    });

    test('a backup with keys warns and is never sent', () {
      final d = BackupJobData(
        job: _job(sections: const ['control', 'keys'], sealed: 'passphrase'),
        site: 'plant',
        where: 'store',
        sendLinks: const [SendLink(link: 'files')],
        sendLink: 'files',
        sendConnection: 's3',
      );
      final vm = backupJobSheet(d);
      expect(d.primary, 'show');
      expect(_choice(vm, 'where').reasons['store'], contains('never sent'));
      expect(
        vm.blocks.whereType<SheetText>().first.text,
        contains('administrator of plant'),
      );
    });

    test('send: offered, then its progress, then a failure said', () {
      BackupJobData data(String sendStatus) => BackupJobData(
        job: _job(sendStatus: sendStatus),
        site: 'plant',
        where: 'store',
        sendLinks: const [SendLink(link: 'files')],
        sendLink: 'files',
        connections: const ['s3'],
        sendConnection: 's3',
      );
      expect(data('').primary, 'send');
      expect(backupJobSheet(data('')).primaryEnabled, isTrue);

      final sending = backupJobSheet(data('sending'));
      expect(sending.blocks.whereType<SheetBar>().single.percent, 40);
      // No second send while one runs.
      expect(data('sending').primary, 'show');

      final failed = backupJobSheet(data('failed'));
      expect(
        failed.blocks.whereType<SheetText>().map((t) => t.text),
        contains('Not sent: the name exists'),
      );
      expect(data('failed').primary, 'send');
    });
  });

  group('Restore', () {
    test('before the check: the upload, then the passphrase', () {
      const picking = RestoreData(site: 'plant');
      expect(restoreSheet(picking).primary, 'Choose the file…');

      const uploading = RestoreData(
        site: 'plant',
        fileName: 'p.wyrm-backup',
        size: 200,
        uploaded: 50,
        uploading: true,
      );
      final vm = restoreSheet(uploading);
      expect(vm.blocks.whereType<SheetBar>().single.percent, 25);
      expect(vm.primaryEnabled, isFalse);

      expect(restoreSheet(_restore()).primary, 'Check the file');
    });

    test('add takes links and storage only', () {
      final d = _restore(check: _check());
      expect(d.sent, {'links', 'storage'});
      final vm = restoreSheet(d);
      expect(_section(vm, 'control').locked, isTrue);
      expect(_section(vm, 'control').on, isFalse);
      expect(_section(vm, 'links').on, isTrue);
      expect(vm.primary, 'Add');
      expect(vm.primaryEnabled, isTrue);
    });

    test('replace is not offered through an upstream, add is', () {
      final d = _restore(check: _check(), viaUpstream: true);
      final vm = restoreSheet(d);
      expect(_choice(vm, 'mode').reasons['replace'], contains('upstream'));
      expect(vm.primaryEnabled, isTrue);
    });

    test('problems of the check block replace', () {
      final vm = restoreSheet(
        _restore(check: _check(problems: const ['registry SCHEMA 21 > 19'])),
      );
      expect(_choice(vm, 'mode').reasons['replace'], isNotNull);
      expect(
        vm.blocks.whereType<SheetCard>().map((c) => c.title),
        contains('registry SCHEMA 21 > 19'),
      );
    });

    test('keys pass three gates: the host, the own gateway, a passphrase', () {
      const chosen = {'control', 'keys'};
      RestoreData data({
        bool exportSecrets = true,
        bool viaUpstream = false,
        int passphrase = 14,
      }) => _restore(
        check: _check(),
        chosen: chosen,
        mode: 'replace',
        exportSecrets: exportSecrets,
        viaUpstream: viaUpstream,
        passphrase: passphrase,
      );
      expect(data().sent, chosen);
      expect(data(exportSecrets: false).sent, {'control'});
      expect(data(exportSecrets: false).keysLocked, contains('export_secrets'));
      expect(data(viaUpstream: true).keysLocked, contains('upstream'));
      expect(data(passphrase: 0).keysLocked, contains('passphrase'));
      expect(
        _section(restoreSheet(data(passphrase: 0)), 'keys').locked,
        isTrue,
      );
    });

    test('keys that differ need Replace the site keys', () {
      RestoreData data({required bool replaceKeys, String keys = 'differ'}) =>
          _restore(
            check: _check(keys: keys),
            chosen: const {'control', 'keys'},
            mode: 'replace',
            passphrase: 14,
            replaceKeys: replaceKeys,
          );
      final held = restoreSheet(data(replaceKeys: false));
      expect(held.primaryEnabled, isFalse);
      expect(
        held.blocks
            .whereType<SheetOption>()
            .firstWhere((o) => o.id == 'replaceKeys')
            .label,
        contains('secrets.bin'),
      );
      expect(restoreSheet(data(replaceKeys: true)).primaryEnabled, isTrue);
      expect(
        restoreSheet(data(replaceKeys: true)).primary,
        'Restore and restart',
      );

      // Another CA: the option warns that everything enrols again.
      final other = restoreSheet(data(replaceKeys: false, keys: 'other'));
      expect(
        other.blocks
            .whereType<SheetOption>()
            .firstWhere((o) => o.id == 'replaceKeys')
            .label,
        contains('enrol again'),
      );

      // The same keys need no confirmation.
      final same = data(replaceKeys: false, keys: 'same');
      expect(same.needsReplaceKeys, isFalse);
    });

    test('a backup of another site is refused before the call', () {
      final vm = restoreSheet(_restore(check: _check(sameSite: false)));
      expect(vm.primaryEnabled, isFalse);
      expect(
        vm.blocks.whereType<SheetCard>().map((c) => c.tone),
        contains(Tone.bad),
      );
    });

    test('after the apply: added live, or the broker restarts', () {
      final added = restoreSheet(
        const RestoreData(
          site: 'plant',
          stage: 'restored',
          result: 'link new1',
        ),
      );
      expect(added.blocks.whereType<SheetBanner>().single.text, 'link new1');
      final restart = restoreSheet(
        const RestoreData(
          site: 'plant',
          stage: 'restarting',
          result: 'control, keys',
        ),
      );
      expect(restart.blocks.whereType<SheetSpinner>(), hasLength(1));
    });
  });

  test('a saved file never replaces one of its name', () {
    final taken = {'/d/a.wyrm-backup', '/d/a (2).wyrm-backup'};
    expect(freeName('/d', 'b.wyrm-backup', taken.contains), '/d/b.wyrm-backup');
    expect(
      freeName('/d', 'a.wyrm-backup', taken.contains),
      '/d/a (3).wyrm-backup',
    );
  });
}
