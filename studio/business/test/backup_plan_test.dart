import 'package:business/redux/backups/models/backups_state.dart';
import 'package:business/wyrm/backup_plan.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_status.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_keys.dart';
import 'package:models/restore_mode.dart';
import 'package:models/send_link.dart';

const List<BackupSection> _broker = [
  BackupSection.control,
  BackupSection.keys,
  BackupSection.dataflows,
  BackupSection.storage,
  BackupSection.history,
  BackupSection.links,
  BackupSection.packages,
  BackupSection.config,
];

BackupsState _form({
  Set<BackupSection> chosen = const {
    BackupSection.control,
    BackupSection.keys,
    BackupSection.storage,
  },
  bool exportSecrets = true,
  String? link,
}) => BackupsState(
  sections: _broker.lock,
  chosen: chosen.lock,
  exportSecrets: exportSecrets,
  link: link,
);

/// What the backup dialogs send to the broker is decided in `business`
/// (re-audit of #135, 6): these are the decisions, each with its test.
void main() {
  group('Back up', () {
    BackupFormPlan plan(
      BackupsState b, {
      bool viaUpstream = false,
      int passphrase = 0,
    }) => backupFormPlanOf(
      b,
      viaUpstream: viaUpstream,
      passphraseLength: passphrase,
    );

    test('keys go in only with a passphrase the broker takes', () {
      final none = plan(_form());
      expect(none.withKeys, isFalse);
      expect(none.sent, {BackupSection.control, BackupSection.storage});
      // ticked and not going: unticked before the call
      expect(none.dropKeys, isTrue);
      expect(none.sendsPassphrase, isFalse);

      final short = plan(_form(), passphrase: minPassphrase - 1);
      expect(
        (short.passphraseOk, short.withKeys, short.dropKeys),
        (
          false,
          false,
          true,
        ),
      );

      final ok = plan(_form(), passphrase: minPassphrase);
      expect((ok.passphraseOk, ok.withKeys, ok.dropKeys), (true, true, false));
      expect(ok.sent, contains(BackupSection.keys));
      expect(ok.sendsPassphrase, isTrue);
    });

    test('the host or an upstream locks secrets, whatever is typed', () {
      final host = plan(_form(exportSecrets: false), passphrase: 14);
      expect(host.secretsLock, SecretsLock.hostForbids);
      expect((host.withKeys, host.sendsPassphrase), (false, false));
      expect(host.sent, isNot(contains(BackupSection.keys)));

      // the upstream is told first
      final up = plan(
        _form(exportSecrets: false),
        viaUpstream: true,
        passphrase: 14,
      );
      expect(up.secretsLock, SecretsLock.viaUpstream);
      expect(
        plan(_form(), viaUpstream: true, passphrase: 14).withKeys,
        isFalse,
      );
    });

    test('keys not ticked: nothing to drop; a link backup has no keys', () {
      final b = _form(chosen: const {BackupSection.control});
      expect(plan(b, passphrase: 14).dropKeys, isFalse);
      expect(plan(b, passphrase: 14).withKeys, isFalse);

      final link = _form(
        link: 'modbus',
        chosen: const {BackupSection.settings, BackupSection.data},
      );
      final p = plan(link, passphrase: 14);
      expect(p.withKeys, isFalse);
      expect(p.sent, {BackupSection.settings, BackupSection.data});
      // its private data is sealed with the passphrase
      expect(p.sendsPassphrase, isTrue);
    });

    test("the sections offered: the broker's, or the link's", () {
      expect(backupSectionsOf(_form(), runsPackage: false), _broker);
      expect(backupSectionsOf(_form(link: 'modbus'), runsPackage: true), [
        BackupSection.settings,
        BackupSection.data,
        BackupSection.package,
        BackupSection.history,
      ]);
      // the broker refuses `package` for a built-in driver
      expect(backupSectionsOf(_form(link: 'modbus'), runsPackage: false), [
        BackupSection.settings,
        BackupSection.data,
        BackupSection.history,
      ]);
    });
  });

  group('a kept backup: what its main button does', () {
    const done = BackupJob(id: 'b1', status: BackupStatus.done);
    const store = BackupsState(
      where: BackupPlace.store,
      sendLinks: IListConst([SendLink(link: 'files')]),
    );

    test('by its status and where it goes', () {
      expect(
        backupJobStepOf(
          const BackupsState(),
          const BackupJob(id: 'b1', status: BackupStatus.failed),
        ),
        BackupJobStep.remove,
      );
      for (final s in [BackupStatus.unknown, BackupStatus.running]) {
        expect(
          backupJobStepOf(const BackupsState(), BackupJob(id: 'b1', status: s)),
          BackupJobStep.nothing,
        );
      }
      expect(
        backupJobStepOf(const BackupsState(), done),
        BackupJobStep.download,
      );
      expect(
        backupJobStepOf(const BackupsState(downloading: 'b1'), done),
        BackupJobStep.cancel,
      );
      // another backup's download is not this one's
      expect(
        backupJobStepOf(const BackupsState(downloading: 'b2'), done),
        BackupJobStep.download,
      );
      expect(
        backupJobStepOf(
          BackupsState(saved: const {'b1': '/tmp/x'}.lock),
          done,
        ),
        BackupJobStep.show,
      );
      expect(
        backupJobStepOf(const BackupsState(where: BackupPlace.broker), done),
        BackupJobStep.show,
      );
    });

    test('a send: offered once, never with the keys, never without a '
        'link', () {
      expect(backupJobStepOf(store, done), BackupJobStep.send);
      for (final s in [BackupSendStatus.sending, BackupSendStatus.done]) {
        expect(
          backupJobStepOf(store, done.copyWith(sendStatus: s)),
          BackupJobStep.show,
        );
      }
      expect(
        backupJobStepOf(
          store,
          done.copyWith(sendStatus: BackupSendStatus.failed),
        ),
        BackupJobStep.send,
      );
      expect(
        backupJobStepOf(
          store,
          done.copyWith(sections: const [BackupSection.keys].lock),
        ),
        BackupJobStep.show,
      );
      expect(
        backupJobStepOf(const BackupsState(where: BackupPlace.store), done),
        BackupJobStep.show,
      );
    });
  });

  group('Restore', () {
    BackupsState form({
      RestoreMode mode = RestoreMode.add,
      Set<BackupSection> chosen = const {
        BackupSection.control,
        BackupSection.links,
        BackupSection.storage,
      },
      bool exportSecrets = true,
      RestoreKeys keys = RestoreKeys.same,
      List<String> problems = const [],
    }) => BackupsState(
      mode: mode,
      chosen: chosen.lock,
      exportSecrets: exportSecrets,
      check: RestoreCheck(keys: keys, problems: problems.lock),
    );
    RestorePlan plan(
      BackupsState b, {
      bool viaUpstream = false,
      int passphrase = 14,
    }) => restorePlanOf(
      b,
      viaUpstream: viaUpstream,
      passphraseLength: passphrase,
    );

    test('add takes links and storage only; the rest ticked is dropped', () {
      final p = plan(form());
      expect(p.takes, {BackupSection.links, BackupSection.storage});
      expect(p.sent, {BackupSection.links, BackupSection.storage});
      expect(p.drop, {BackupSection.control});
      expect(p.needsReplaceKeys, isFalse);
    });

    test('replace takes its sections; config is never restored', () {
      final p = plan(
        form(
          mode: RestoreMode.replace,
          chosen: const {
            BackupSection.control,
            BackupSection.keys,
            BackupSection.config,
          },
        ),
      );
      expect(p.takes, RestoreMode.replace.sections.toSet());
      expect(p.sent, {BackupSection.control, BackupSection.keys});
      expect(p.drop, {BackupSection.config});
    });

    test('keys pass three gates: the upstream, the host, a passphrase', () {
      final b = form(
        mode: RestoreMode.replace,
        chosen: const {BackupSection.control, BackupSection.keys},
      );
      expect(plan(b).keysLock, isNull);
      for (final (p, lock) in [
        (plan(b, viaUpstream: true), SecretsLock.viaUpstream),
        (
          plan(
            b.copyWith(exportSecrets: false),
          ),
          SecretsLock.hostForbids,
        ),
        (plan(b, passphrase: 0), SecretsLock.noPassphrase),
      ]) {
        expect(p.keysLock, lock);
        expect(p.takes, isNot(contains(BackupSection.keys)));
        expect(p.sent, {BackupSection.control});
        expect(p.drop, {BackupSection.keys});
        expect(p.needsReplaceKeys, isFalse);
      }
    });

    test("keys that are not this broker's need a confirmation", () {
      BackupsState b(RestoreKeys keys) => form(
        mode: RestoreMode.replace,
        chosen: const {BackupSection.control, BackupSection.keys},
        keys: keys,
      );
      expect(plan(b(RestoreKeys.differ)).needsReplaceKeys, isTrue);
      expect(plan(b(RestoreKeys.other)).needsReplaceKeys, isTrue);
      expect(plan(b(RestoreKeys.same)).needsReplaceKeys, isFalse);
      expect(plan(b(RestoreKeys.none)).needsReplaceKeys, isFalse);
      // not restored: nothing to confirm
      expect(
        plan(b(RestoreKeys.differ), passphrase: 0).needsReplaceKeys,
        isFalse,
      );
    });

    test('a replace is locked through an upstream or by problems', () {
      expect(plan(form()).replaceLock, isNull);
      expect(
        plan(form(), viaUpstream: true).replaceLock,
        ReplaceLock.viaUpstream,
      );
      expect(
        plan(form(problems: const ['registry SCHEMA 21 > 19'])).replaceLock,
        ReplaceLock.problems,
      );
    });
  });
}
