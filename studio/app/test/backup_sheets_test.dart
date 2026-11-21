import 'dart:io';
import 'dart:typed_data';

import 'package:app/common/files.dart';
import 'package:app/mappers/backup_mappers.dart';
import 'package:app/mappers/link_install_mappers.dart';
import 'package:app/mappers/links_mappers.dart';
import 'package:app/mappers/system_mappers.dart';
import 'package:business/redux/backups/models/backups_state.dart';
import 'package:business/wyrm/backup_plan.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:models/backup_status.dart';
import 'package:models/backup_step.dart';
import 'package:models/backups_read.dart';
import 'package:models/link_mode.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_keys.dart';
import 'package:models/restore_link_state.dart';
import 'package:models/restore_mode.dart';
import 'package:models/schema_pair.dart';
import 'package:models/send_link.dart';
import 'package:ui/indicators/level_badge.dart';
import 'package:ui/models/disabled.dart';
import 'package:ui/models/link_run_mode.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/backup_data.dart';
import 'package:ui/overlays/backup_sheet.dart';
import 'package:ui/overlays/task_sheet.dart';
import 'package:ui/pages/links_data.dart';
import 'package:ui/pages/system_data.dart';

// The data of these tests is made as the app makes it: the domain values
// of `models` (read from their wire names, as the decoders read them)
// through the mappers of `app/lib/mappers/backup_mappers.dart`.

/// The sections of [names] (the broker's names) as the dialog's parts.
Set<BackupPart> _parts(Iterable<String> names) => {
  for (final n in names) BackupSection.fromWire(n)!.part,
};

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

/// The state of the backup dialog these tests draw.
BackupsState _state({
  String? link,
  Set<String> chosen = const {},
  bool exportSecrets = true,
  BackupPlace where = BackupPlace.computer,
  List<SendLink> sendLinks = const [],
  String? sendConnection,
}) => BackupsState(
  availability: BackupsRead.read,
  sections: [for (final s in _sections) BackupSection.fromWire(s)!].lock,
  link: link,
  chosen: {for (final s in chosen) BackupSection.fromWire(s)!}.lock,
  estimate: const {
    BackupSection.control: 1200,
    BackupSection.keys: 48,
    BackupSection.storage: 2000,
  }.lock,
  exportSecrets: exportSecrets,
  where: where,
  sendLinks: sendLinks.lock,
  sendLink: sendLinks.isEmpty ? null : sendLinks.first.link,
  connections: const ['s3'].lock,
  sendConnection: sendConnection,
);

/// The *Back up* form as the app builds it: what goes to the broker is
/// decided by `business` (`backupFormPlanOf`), the mapper only maps.
BackupFormData _form({
  Set<String> chosen = const {'control', 'keys', 'storage'},
  bool exportSecrets = true,
  bool viaUpstream = false,
  int passphrase = 0,
  BackupPlace where = BackupPlace.computer,
  List<SendLink> sendLinks = const [],
  String? sendConnection,
  String? link,
  Disabled? reason,
}) {
  final b = _state(
    link: link,
    chosen: chosen,
    exportSecrets: exportSecrets,
    where: where,
    sendLinks: sendLinks,
    sendConnection: sendConnection,
  );
  return backupFormDataOf(
    site: 'plant',
    b: b,
    plan: backupFormPlanOf(
      b,
      viaUpstream: viaUpstream,
      passphraseLength: passphrase,
    ),
    linkIds: const ['modbus', 's7'],
    reason: reason,
  );
}

BackupJob _jobModel({
  String status = 'done',
  List<String> sections = const ['control', 'storage'],
  String sealed = 'none',
  String sendStatus = '',
  BackupStep step = const BackupStep.section(BackupSection.storage),
}) => BackupJob(
  id: 'b1',
  name: 'plant-2026-11-13-1540.wyrm-backup',
  sections: [for (final s in sections) BackupSection.fromWire(s)!].lock,
  sealed: BackupSealed.fromWire(sealed)!,
  status: BackupStatus.fromWire(status)!,
  progress: status == 'done' ? 100 : 46,
  step: step,
  size: 4096,
  sha256: 'ab' * 32,
  expires: DateTime.utc(2026, 11, 20, 15, 40, 12),
  error: status == 'failed' ? 'no room on the disk' : '',
  sendStatus: BackupSendStatus.fromWire(sendStatus)!,
  sendProgress: 40,
  sentTo: 'files/s3/files/backups/x',
  sendError: 'the name exists',
);

/// The dialog of a kept backup as the app builds it: what its main button
/// does, and whether it may, is decided by `business` (`backupJobPlanOf`).
BackupJobData _jobData({
  BackupJob? job,
  BackupPlace where = BackupPlace.computer,
  List<SendLink> sendLinks = const [],
  String? sendConnection,
  bool downloading = false,
  int downloaded = 0,
  String? savedTo,
}) {
  final j = job ?? _jobModel();
  final b =
      _state(
        where: where,
        sendLinks: sendLinks,
        sendConnection: sendConnection,
      ).copyWith(
        downloading: downloading ? j.id : null,
        downloaded: downloaded,
        saved: {j.id: ?savedTo}.lock,
      );
  return backupJobDataOf(
    site: 'plant',
    b: b,
    job: j,
    plan: backupJobPlanOf(b, j),
  );
}

RestoreCheck _check({
  String keys = 'same',
  bool sameSite = true,
  List<String> problems = const [],
}) => RestoreCheck(
  site: sameSite ? 'plant' : 'other',
  sameSite: sameSite,
  created: DateTime(2026, 11, 20, 15, 40),
  broker: '0.1.0',
  sealed: BackupSealed.passphrase,
  schemas: const {'registry': SchemaPair(backup: 18, here: 19)}.lock,
  sections: const {
    BackupSection.control: 1200,
    BackupSection.keys: 48,
    BackupSection.history: 9000,
    BackupSection.links: 300,
    BackupSection.storage: 20,
    BackupSection.config: 6,
  }.lock,
  keys: RestoreKeys.fromWire(keys)!,
  keysDiffer: [if (keys == 'differ') 'secrets.bin'].lock,
  links: const {
    'modbus': RestoreLinkState.exists,
    'new1': RestoreLinkState.fresh,
  }.lock,
  problems: problems.lock,
);

/// The *Restore* form as the app builds it: what goes to the broker is
/// decided by `business` (`restorePlanOf`).
RestoreData _restore({
  RestoreCheck? check,
  Set<String> chosen = const {'control', 'links', 'storage'},
  RestoreMode mode = RestoreMode.add,
  bool exportSecrets = true,
  bool viaUpstream = false,
  int passphrase = 0,
  bool replaceKeys = false,
}) {
  final b = _state(chosen: chosen, exportSecrets: exportSecrets).copyWith(
    upload: 'u1',
    uploadName: 'plant.wyrm-backup',
    uploadSize: 100,
    uploaded: 100,
    check: check,
    mode: mode,
    replaceKeys: replaceKeys,
  );
  return restoreDataOf(
    site: 'plant',
    b: b,
    plan: restorePlanOf(
      b,
      viaUpstream: viaUpstream,
      passphraseLength: passphrase,
    ),
    file: restoreFilePlanOf(b),
    view: RestoreView.form,
  );
}

/// The card of the section the broker names [id].
SheetSection _section(TaskSheetVm vm, String id) => vm.blocks
    .whereType<SheetSection>()
    .firstWhere((s) => s.name == BackupSection.fromWire(id)!.part.label);

/// The option of the choice labelled [label] that says [option].
SheetChoiceOption _option(TaskSheetVm vm, String label, String option) => vm
    .blocks
    .whereType<SheetChoice>()
    .firstWhere((c) => c.label == label)
    .options
    .firstWhere((o) => o.label == option);

/// Why a file store cannot be chosen, or null.
String? _storeReason(TaskSheetVm vm) =>
    _option(vm, S.current.bakWhere, BackupTarget.store.label).reason;

/// Why a replace cannot be chosen, or null.
String? _replaceReason(TaskSheetVm vm) =>
    _option(vm, S.current.rstHow, RestoreHow.replace.label).reason;

/// The states of the backup dialogs (boards `Backup*`, `LinkBackup`, spec
/// `updates-backups.md` §2, §4).
void main() {
  setUpAll(() => S.load(const Locale('en')));

  group('Back up', () {
    test('keys go in only with a passphrase the broker takes', () {
      final none = _form();
      expect(none.sent.contains(BackupPart.keys), isFalse);
      expect(none.sent, _parts(const ['control', 'storage']));
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
      expect(ok.sent.contains(BackupPart.keys), isTrue);
      expect(_section(backupFormSheet(ok), 'keys').on, isTrue);
      expect(backupFormSheet(ok).primaryEnabled, isTrue);
    });

    test('export_secrets false locks keys and the passphrase with it', () {
      final d = _form(exportSecrets: false, passphrase: 14);
      final vm = backupFormSheet(d);
      expect(d.sent.contains(BackupPart.keys), isFalse);
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
      expect(d.sent.contains(BackupPart.keys), isFalse);
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
      expect(_storeReason(none), contains('send_links'));

      const links = [SendLink(link: 'files', folder: 'site/backups')];
      final pick = backupFormSheet(
        _form(where: BackupPlace.store, sendLinks: links),
      );
      expect(_storeReason(pick), isNull);
      // No connection yet: the primary waits for one.
      expect(pick.primaryEnabled, isFalse);

      final ready = backupFormSheet(
        _form(where: BackupPlace.store, sendLinks: links, sendConnection: 's3'),
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
        _form(where: BackupPlace.store, sendLinks: links, passphrase: 14),
      );
      expect(_storeReason(keys), contains('never sent'));
    });

    test('without config the dialog is locked with the reason', () {
      final vm = backupFormSheet(
        _form(reason: const NeedsLevel(AccessLevel.config, 'sys/backups')),
      );
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
        _jobData(
          job: _jobModel(status: 'running'),
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
      final d = _jobData(
        job: _jobModel(status: 'failed'),
      );
      final vm = backupJobSheet(d);
      expect(vm.blocks.whereType<SheetBanner>().single.tone, Tone.bad);
      expect(
        vm.blocks.whereType<SheetBanner>().single.text,
        'no room on the disk',
      );
      expect(d.primary, BackupDo.remove);
    });

    test('done: download, then show; cancel while it runs', () {
      final done = _jobData();
      expect(done.primary, BackupDo.download);
      expect(backupJobSheet(done).primary, 'Download…');

      final running = _jobData(
        job: _jobModel(),
        downloading: true,
        downloaded: 1024,
      );
      expect(running.primary, BackupDo.cancel);
      expect(
        backupJobSheet(running).blocks.whereType<SheetBar>().single.percent,
        25,
      );

      final saved = _jobData(
        job: _jobModel(),
        savedTo: '/tmp/x.wyrm-backup',
      );
      expect(saved.primary, BackupDo.show);
      expect(
        backupJobSheet(saved).blocks.whereType<SheetText>().map((t) => t.text),
        contains(contains('/tmp/x.wyrm-backup')),
      );
    });

    test('a backup with keys warns and is never sent', () {
      final d = _jobData(
        job: _jobModel(
          sections: const ['control', 'keys'],
          sealed: 'passphrase',
        ),
        where: BackupPlace.store,
        sendLinks: const [SendLink(link: 'files')],
        sendConnection: 's3',
      );
      final vm = backupJobSheet(d);
      expect(d.primary, BackupDo.show);
      expect(_storeReason(vm), contains('never sent'));
      expect(
        vm.blocks.whereType<SheetText>().first.text,
        contains('administrator of plant'),
      );
    });

    test('send: offered, then its progress, then a failure said', () {
      BackupJobData data(String sendStatus) => _jobData(
        job: _jobModel(sendStatus: sendStatus),
        where: BackupPlace.store,
        sendLinks: const [SendLink(link: 'files')],
        sendConnection: 's3',
      );
      expect(data('').primary, BackupDo.send);
      expect(backupJobSheet(data('')).primaryEnabled, isTrue);

      final sending = backupJobSheet(data('sending'));
      expect(sending.blocks.whereType<SheetBar>().single.percent, 40);
      // No second send while one runs.
      expect(data('sending').primary, BackupDo.show);

      final failed = backupJobSheet(data('failed'));
      expect(
        failed.blocks.whereType<SheetText>().map((t) => t.text),
        contains('Not sent: the name exists'),
      );
      expect(data('failed').primary, BackupDo.send);
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
        file: RestoreFileView.uploading,
        fileStop: RestoreFileStop.uploading,
      );
      final vm = restoreSheet(uploading);
      expect(vm.blocks.whereType<SheetBar>().single.percent, 25);
      expect(vm.primaryEnabled, isFalse);
      // the reason is the plan's, named here
      expect(vm.primaryReason, 'The file is still going to the broker');

      // as the app builds it: the step and its lock come from `business`
      RestoreData at(BackupsState b) => restoreDataOf(
        site: 'plant',
        b: b,
        plan: restorePlanOf(b, viaUpstream: false, passphraseLength: 0),
        file: restoreFilePlanOf(b),
        view: RestoreView.form,
      );
      final none = restoreSheet(at(const BackupsState()));
      expect((none.primary, none.primaryEnabled), ('Choose the file…', true));
      final going = at(
        const BackupsState(uploadName: 'p.wyrm-backup', uploadSize: 200),
      );
      expect(
        (going.file, going.fileStop),
        (
          RestoreFileView.uploading,
          RestoreFileStop.uploading,
        ),
      );
      expect(restoreSheet(going).primaryEnabled, isFalse);
      for (final b in RestoreFileStep.values) {
        expect(b.ui.name, b.name);
      }
      for (final b in RestoreFileBlock.values) {
        expect(b.ui.name, b.name);
      }

      expect(restoreSheet(_restore()).primary, 'Check the file');
    });

    test('add takes links and storage only', () {
      final d = _restore(check: _check());
      expect(d.sent, _parts(const ['links', 'storage']));
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
      expect(_replaceReason(vm), contains('upstream'));
      expect(vm.primaryEnabled, isTrue);
    });

    test('problems of the check block replace', () {
      final vm = restoreSheet(
        _restore(check: _check(problems: const ['registry SCHEMA 21 > 19'])),
      );
      expect(_replaceReason(vm), isNotNull);
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
        mode: RestoreMode.replace,
        exportSecrets: exportSecrets,
        viaUpstream: viaUpstream,
        passphrase: passphrase,
      );
      expect(data().sent, _parts(chosen));
      expect(data(exportSecrets: false).sent, _parts(const ['control']));
      expect(
        data(exportSecrets: false).keysLock!.label,
        contains('export_secrets'),
      );
      expect(data(viaUpstream: true).keysLock!.label, contains('upstream'));
      expect(data(passphrase: 0).keysLock!.label, contains('passphrase'));
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
            mode: RestoreMode.replace,
            passphrase: 14,
            replaceKeys: replaceKeys,
          );
      final held = restoreSheet(data(replaceKeys: false));
      expect(held.primaryEnabled, isFalse);
      expect(
        held.blocks
            .whereType<SheetOption>()
            // the confirmation of the keys comes before the rights
            .first
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
            // the confirmation of the keys comes before the rights
            .first
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
          view: RestoreView.restored,
          result: 'link new1',
        ),
      );
      expect(added.blocks.whereType<SheetBanner>().single.text, 'link new1');
      final restart = restoreSheet(
        RestoreData(
          site: 'plant',
          view: BackupStage.restarting.restoreView!,
          staged: _parts(const ['control', 'keys']).toList(),
        ),
      );
      expect(restart.blocks.whereType<SheetSpinner>(), hasLength(1));
      // the staged sections are said in the language on screen
      expect(
        restart.blocks.whereType<SheetFacts>().single.facts.single.value,
        '${BackupPart.control.label}, ${BackupPart.keys.label}',
      );
    });
  });

  group('after a replace (review point 5)', () {
    TaskSheetVm at(BackupStage stage, [String? result]) => restoreSheet(
      RestoreData(site: 'plant', view: stage.restoreView!, result: result),
    );

    test('applied, not applied, unknown', () {
      expect(
        at(BackupStage.applied).blocks.whereType<SheetBanner>().single.tone,
        Tone.good,
      );
      final failed = at(BackupStage.notApplied, 'registry: bad chain');
      expect(failed.blocks.whereType<SheetBanner>().single.tone, Tone.bad);
      expect(
        failed.blocks.whereType<SheetBanner>().single.text,
        'registry: bad chain',
      );
      expect(
        at(BackupStage.unknown).blocks.whereType<SheetBanner>().single.tone,
        Tone.warn,
      );
      expect(at(BackupStage.applied).primary, isNull);
    });

    test('lost: the user is sent to log in', () {
      final vm = at(BackupStage.lost);
      expect(
        vm.blocks.whereType<SheetBanner>().single.text,
        contains('Log in'),
      );
      expect(vm.primary, 'Log in again');
      expect(vm.blocks.whereType<SheetSpinner>(), isEmpty);
    });
  });

  group('the controls report typed values (studio-rules §2, §7)', () {
    test('a section, a history range, a link, a place, a store', () {
      final got = <Object?>[];
      const links = [SendLink(link: 'files', folder: 'site/backups')];
      final vm = backupFormSheet(
        _form(
          chosen: const {'control', 'history', 'links', 'storage'},
          where: BackupPlace.store,
          sendLinks: links,
          sendConnection: 's3',
        ),
        onSection: (part, {required on}) => got.add((part.section, on)),
        onHistoryRange: (range) => got.add(range.days),
        onLink: got.add,
        onPassphrase: (text) => got.add(text.length),
        onWhere: (t) => got.add(t.place),
        onSendLink: (link) => got.add('link $link'),
        onSendConnection: (c) => got.add('connection $c'),
        onSendPath: (path) => got.add('path $path'),
      );

      _section(vm, 'storage').onChanged!(false);
      // a section that is always in cannot be unticked
      expect(_section(vm, 'control').locked, isTrue);
      for (final chip in _section(vm, 'history').chips) {
        chip.onTap!();
      }
      _section(vm, 'links').chips.first.onTap!();
      vm.blocks.whereType<SheetField>().first.onChanged!('x' * 14);
      _option(vm, S.current.bakWhere, BackupTarget.broker.label).onPick!();
      _option(vm, S.current.bakSendLink, 'files').onPick!();
      _option(vm, S.current.bakSendConnection, 's3').onPick!();
      vm.blocks.whereType<SheetField>().last.onChanged!('daily/x');

      expect(got, [
        (BackupSection.storage, false),
        7,
        30,
        90,
        // all of it
        0,
        'modbus',
        14,
        BackupPlace.broker,
        'link files',
        'connection s3',
        'path daily/x',
      ]);
      // a field is known by its slot, never by a text
      expect(vm.blocks.whereType<SheetField>().map((f) => f.slot), [
        SheetSlot.backupPassphrase,
        SheetSlot.backupSendPath,
      ]);
    });

    test('without a listener a control cannot be used', () {
      final vm = backupFormSheet(_form());
      expect(_section(vm, 'storage').onChanged, isNull);
      expect(vm.blocks.whereType<SheetField>().single.onChanged, isNull);
      expect(
        _option(vm, S.current.bakWhere, BackupTarget.broker.label).onPick,
        isNull,
      );
    });

    test('a restore: its sections, its mode, its confirmations', () {
      final got = <Object?>[];
      final vm = restoreSheet(
        _restore(
          check: _check(keys: 'differ'),
          chosen: const {'control', 'keys'},
          mode: RestoreMode.replace,
          passphrase: 14,
        ),
        onSection: (part, {required on}) => got.add((part.section, on)),
        onMode: (how) => got.add(how.mode),
        onReplaceKeys: (on) => got.add('replace keys $on'),
        onAccept: (on) => got.add('accept $on'),
        onPassphrase: (text) => got.add(text.length),
      );

      _section(vm, 'history').onChanged!(true);
      _option(vm, S.current.rstHow, RestoreHow.add.label).onPick!();
      final options = vm.blocks.whereType<SheetOption>().toList();
      options.first.onChanged!(true);
      options.last.onChanged!(true);
      vm.blocks.whereType<SheetField>().single.onChanged!('x' * 12);

      expect(got, [
        (BackupSection.history, true),
        RestoreMode.add,
        'replace keys true',
        'accept true',
        12,
      ]);
    });

    test('a backup: where it goes and its removal', () {
      final got = <Object?>[];
      final vm = backupJobSheet(
        _jobData(),
        onWhere: (t) => got.add(t.place),
        onRemove: () => got.add('remove'),
      );

      _option(vm, S.current.bakWhere, BackupTarget.computer.label).onPick!();
      vm.blocks.whereType<SheetRow>().single.onAction!();

      expect(got, [BackupPlace.computer, 'remove']);
      // a kept backup is never moved to "the broker": it is there
      expect(
        vm.blocks.whereType<SheetChoice>().single.options.map((o) => o.label),
        [BackupTarget.computer.label, BackupTarget.store.label],
      );
    });
  });

  group('why a step may not start is named, not decided, by the sheet '
      '(audit 3 of #135, 2)', () {
    tearDown(() => S.load(const Locale('en')));

    test('every reason of the plans maps to one the sheets word', () {
      expect(
        [for (final b in BackupBlock.values) b.ui.name],
        [
          for (final b in BackupBlock.values) b.name,
        ],
      );
      expect(
        [for (final b in SendBlock.values) b.ui.name],
        [
          for (final b in SendBlock.values) b.name,
        ],
      );
      expect(
        [for (final b in RestoreBlock.values) b.ui.name],
        [
          for (final b in RestoreBlock.values) b.name,
        ],
      );
      expect(
        [for (final b in KeysBlock.values) b.ui.name],
        [
          for (final b in KeysBlock.values) b.name,
        ],
      );
      expect(
        [for (final b in StoreBlock.values) b.ui.name],
        [
          for (final b in StoreBlock.values) b.name,
        ],
      );
    });

    test('the button says the reason the plan gave, en and uk', () async {
      List<String?> said() => [
        // Back up
        backupFormSheet(_form(passphrase: 5)).primaryReason,
        backupFormSheet(_form(where: BackupPlace.store)).primaryReason,
        backupFormSheet(
          _form(
            where: BackupPlace.store,
            sendLinks: const [SendLink(link: 'files')],
          ),
        ).primaryReason,
        // a kept backup
        backupJobSheet(
          _jobData(
            where: BackupPlace.store,
            sendLinks: const [SendLink(link: 'files')],
          ),
        ).primaryReason,
        // Restore
        restoreSheet(_restore(check: _check(sameSite: false))).primaryReason,
        restoreSheet(
          _restore(check: _check(), chosen: const {'control'}),
        ).primaryReason,
        restoreSheet(
          _restore(
            check: _check(problems: const ['the registry is newer']),
            mode: RestoreMode.replace,
          ),
        ).primaryReason,
        restoreSheet(
          _restore(
            check: _check(),
            mode: RestoreMode.replace,
            viaUpstream: true,
          ),
        ).primaryReason,
        restoreSheet(
          _restore(
            check: _check(keys: 'differ'),
            mode: RestoreMode.replace,
            chosen: const {'control', 'keys'},
            passphrase: 14,
          ),
        ).primaryReason,
        RestoreStop.notChecked.label,
      ];

      expect(said(), [
        S.current.bakPassphraseShort(12),
        S.current.bakNoSendLinks,
        S.current.bakChooseConnection,
        S.current.bakChooseConnection,
        S.current.rstOtherSiteNote,
        S.current.rstNothingTicked,
        S.current.rstReplaceProblems,
        S.current.rstReplaceUpstream,
        S.current.rstConfirmKeys,
        'Upload and check the file first',
      ]);
      final en = said();
      await S.load(const Locale('uk'));
      final uk = said();
      expect(uk.last, 'Спершу завантаж і перевір файл');
      for (final (i, text) in uk.indexed) {
        expect(text, isNot(en[i]), reason: '${en[i]}');
      }
    });

    test('a blocked button is locked; a free one is not', () {
      for (final vm in [
        backupFormSheet(_form(passphrase: 5)),
        backupFormSheet(_form(where: BackupPlace.store)),
        restoreSheet(_restore(check: _check(sameSite: false))),
        restoreSheet(_restore(check: _check(), chosen: const {'control'})),
      ]) {
        expect(vm.primaryEnabled, isFalse, reason: '${vm.primaryReason}');
      }
      expect(restoreSheet(_restore(check: _check())).primaryEnabled, isTrue);
      expect(backupFormSheet(_form()).primaryEnabled, isTrue);
      // Show and Cancel need no right; Download does
      const noRight = NeedsLevel(AccessLevel.config, 'sys/backups');
      BackupJobData job({String? savedTo, bool downloading = false}) =>
          _jobData(savedTo: savedTo, downloading: downloading);
      BackupJobData lacking(BackupJobData d) => BackupJobData(
        job: d.job,
        site: d.site,
        primary: d.primary,
        primaryNeedsRights: d.primaryNeedsRights,
        stop: d.stop,
        downloading: d.downloading,
        savedTo: d.savedTo,
        reason: noRight,
      );
      expect(backupJobSheet(lacking(job())).primaryEnabled, isFalse);
      expect(
        backupJobSheet(lacking(job(savedTo: '/tmp/x'))).primaryEnabled,
        isTrue,
      );
      expect(
        backupJobSheet(lacking(job(downloading: true))).primaryEnabled,
        isTrue,
      );
    });
  });

  group('the domain of backups as the dialogs draw it (studio-rules §3)', () {
    test('every section, place and mode maps there and back', () {
      for (final s in BackupSection.values) {
        expect(s.part.section, s);
        expect(s.part.name, s.name);
        expect(s.part.label, isNotEmpty);
        expect(s.part.note(ofLink: false), isNotEmpty);
      }
      expect(
        {for (final s in BackupSection.values) s.part},
        {
          ...BackupPart.values,
        },
      );
      // the sections whose checkbox is fixed are the domain's, not ui's
      expect(_form().fixed, {
        for (final s in BackupSection.values)
          if (s.always) s.part,
      });
      for (final p in BackupPlace.values) {
        expect(p.target.place, p);
      }
      for (final m in RestoreMode.values) {
        expect(m.how.mode, m);
      }
      for (final k in RestoreKeys.values) {
        expect(k.found.name, k.name);
      }
    });

    test('the stages of a restore, and those that are not one', () {
      expect(BackupStage.choose.restoreView, isNull);
      expect(BackupStage.link.restoreView, isNull);
      expect(BackupStage.job.restoreView, isNull);
      expect(BackupStage.restore.restoreView, RestoreView.form);
      expect(BackupStage.notApplied.restoreView, RestoreView.notApplied);
      expect(
        {
          for (final s in BackupStage.values) ?s.restoreView,
        },
        {...RestoreView.values},
      );
    });

    test('a job: its step is a section, the writing, or none', () {
      final copying = _jobModel(status: 'running').facts;
      expect(copying.view, BackupJobView.working);
      expect(copying.step, BackupPart.storage);
      expect(copying.writing, isFalse);

      final writing = _jobModel(
        status: 'running',
        step: const BackupStep.writing(),
      );
      expect(writing.facts.step, isNull);
      expect(writing.facts.writing, isTrue);
      final vm = backupJobSheet(_jobData(job: writing));
      expect(vm.blocks.whereType<SheetBar>().single.text, 'Writing the file');
      // every section is copied by then
      expect(
        vm.blocks.whereType<SheetSteps>().single.steps.map((s) => s.state),
        [SheetStepState.done, SheetStepState.done],
      );

      final none = _jobModel(status: 'running', step: const BackupStep.none());
      expect(none.facts.step, isNull);
      expect(
        backupJobSheet(
          _jobData(job: none),
        ).blocks.whereType<SheetSteps>().single.steps.map((s) => s.state),
        [SheetStepState.todo, SheetStepState.todo],
      );
    });

    test('a link backup says how its link runs in words, not by a code', () {
      final vm = backupFormSheet(
        BackupFormData(
          site: 'plant',
          link: 'modbus',
          linkMode: LinkMode.process.ui,
          linkDriver: 'pkg:modbus',
          sections: _parts(const ['settings', 'data']).toList(),
          chosen: _parts(const ['settings']),
        ),
      );
      expect(
        vm.blocks.whereType<SheetFacts>().single.facts.single.value,
        'modbus · ${LinkRunMode.process.label} · pkg:modbus',
      );
      // a link that is not known yet says nothing of how it runs
      expect(
        backupFormSheet(_form(link: 'modbus')).blocks.whereType<SheetFacts>(),
        isEmpty,
      );
    });

    test('why no backup is offered: no sys/backups, or one not read', () {
      expect(BackupsRead.read.off, isNull);
      expect(BackupsRead.absent.off, BackupsOff.absent);
      expect(BackupsRead.unreadable.off, BackupsOff.unreadable);
      // not read yet, or the read failed: neither is "a wyrmd before…"
      expect(BackupsRead.unknown.off, BackupsOff.notReadYet);
      expect(BackupsRead.failed.off, BackupsOff.readFailed);
      for (final off in const [BackupsOff.notReadYet, BackupsOff.readFailed]) {
        expect(off.label, isNot(contains('ADR 0048')));
        expect(off.label, isNot(BackupsOff.unreadable.label));
      }
      // two reasons, two sentences: the second is not "a wyrmd before…"
      expect(BackupsOff.absent.label, contains('ADR 0048'));
      expect(BackupsOff.unreadable.label, contains('does not read'));
      expect(BackupsOff.unreadable.label, isNot(contains('ADR 0048')));

      SysBackupsData? card(BackupsRead a) => a.card(
        keepDays: 7,
        rows: const [BackupJob(id: 'b1')],
        unread: const ['b2'].lock,
      );
      expect(card(BackupsRead.absent), isNull);
      expect(card(BackupsRead.unknown), isNull);
      expect(card(BackupsRead.unreadable), const SysBackupsUnreadable());
      expect(card(BackupsRead.failed), const SysBackupsFailed());
      expect(
        card(BackupsRead.read),
        isA<SysBackupsRead>()
            .having((r) => r.keepDays, 'keepDays', 7)
            .having((r) => [for (final j in r.rows) j.id], 'rows', ['b1'])
            // a backup that was not read is still a row
            .having((r) => r.unread, 'unread', ['b2']),
      );
    });

    test('a kept backup lists its sections by their labels', () {
      final row = BackupJob(
        id: 'b1',
        sections: const [BackupSection.control, BackupSection.keys].lock,
      ).row;
      expect(row.sections, [BackupPart.control, BackupPart.keys]);
    });

    test('the check: the schemas that differ and the links, in words', () {
      final vm = restoreSheet(_restore(check: _check()));
      final cards = vm.blocks.whereType<SheetCard>().toList();
      expect(
        cards.map((c) => c.detail),
        containsAll(['registry 18 → 19', 'modbus: exists here, new1: new']),
      );
      expect(
        cards.first.detail,
        contains('2026-11-20 15:40'),
      );
    });
  });

  group('a file name from the broker (review point 12)', () {
    test('only the last segment, and only a plain name', () {
      expect(safeFileName('plant-1.wyrm-backup'), 'plant-1.wyrm-backup');
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName(r'..\..\x.wyrm-backup'), 'x.wyrm-backup');
      expect(safeFileName('/abs/a.wyrm-link'), 'a.wyrm-link');
      for (final bad in [
        '',
        '..',
        '.',
        'a/..',
        'x/',
        'con',
        'NUL.txt',
        'a:b',
        'a\x00b',
        'q?',
        'dot.',
      ]) {
        expect(safeFileName(bad), isNull, reason: bad);
      }
    });
  });

  group('a download on disk (review point 1)', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('wyrm-save');
      directoryPicker = (_) async => dir.path;
    });
    tearDown(() {
      directoryPicker = null;
      dir.deleteSync(recursive: true);
    });

    List<String> names() => [
      for (final f in dir.listSync()) f.path.split(Platform.pathSeparator).last,
    ]..sort();

    test('the file has its name only after commit', () async {
      final f = (await saveInto('a.wyrm-backup', fallback: 'b'))!;
      await f.write(Uint8List.fromList([1, 2, 3]));
      expect(names(), ['a.wyrm-backup.part']);
      await f.commit();
      expect(names(), ['a.wyrm-backup']);
      expect(File(f.path).readAsBytesSync(), [1, 2, 3]);
    });

    test('discard removes the part and never throws, also twice', () async {
      final f = (await saveInto('a.wyrm-backup', fallback: 'b'))!;
      await f.write(Uint8List.fromList([1]));
      await f.discard();
      await f.discard();
      expect(names(), isEmpty);
    });

    test('a stale part goes; a file that exists is never replaced', () async {
      File('${dir.path}/a.wyrm-backup').writeAsStringSync('old');
      File('${dir.path}/a (2).wyrm-backup.part').writeAsStringSync('stale');
      final f = (await saveInto('a.wyrm-backup', fallback: 'b'))!;
      await f.write(Uint8List.fromList([9]));
      await f.commit();
      expect(names(), ['a (2).wyrm-backup', 'a.wyrm-backup']);
      expect(File('${dir.path}/a.wyrm-backup').readAsStringSync(), 'old');
      expect(File(f.path).readAsBytesSync(), [9]);
    });

    test('a name that cannot be a file name becomes the fallback', () async {
      final f = (await saveInto('..', fallback: 'backup.wyrm-backup'))!;
      await f.commit();
      expect(names(), ['backup.wyrm-backup']);
    });

    test('a picked file is read in whole parts', () async {
      final path = '${dir.path}/in.wyrm-link';
      File(path).writeAsBytesSync([for (var i = 0; i < 1000; i++) i % 251]);
      filePathPicker = (_) async => path;
      addTearDown(() => filePathPicker = null);
      final f = (await pickFile())!;
      expect(f.size, 1000);
      expect((await f.read(0, 400)).length, 400);
      expect((await f.read(900, 400)).length, 100);
      expect(await f.read(990, 4), [
        990 % 251,
        991 % 251,
        992 % 251,
        993 % 251,
      ]);
      await f.close();
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
