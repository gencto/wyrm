import 'dart:convert';
import 'dart:typed_data';

import 'package:business/wyrm/decode/backup_job.dart';
import 'package:business/wyrm/decode/decoded.dart';
import 'package:business/wyrm/decode/package_manifest.dart';
import 'package:business/wyrm/decode/restore.dart';
import 'package:business/wyrm/decode/transfer.dart';
import 'package:business/wyrm/decode/unreadable.dart';
import 'package:business/wyrm/failures.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_link_facts.dart';
import 'package:models/backup_manifest.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:models/backup_step.dart';
import 'package:models/error_call.dart';
import 'package:models/error_hint.dart';
import 'package:models/error_kind.dart';
import 'package:models/file_part.dart';
import 'package:models/link_mode.dart';
import 'package:models/manifest_fault.dart';
import 'package:models/manifest_problem.dart';
import 'package:models/package_kind.dart';
import 'package:models/package_manifest.dart';
import 'package:models/package_manifest_read.dart';
import 'package:models/restore_answer.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_end.dart';
import 'package:models/restore_keys.dart';
import 'package:models/restore_link_state.dart';
import 'package:models/restore_mode.dart';
import 'package:models/restore_record.dart';
import 'package:models/schema_pair.dart';
import 'package:models/stated.dart';
import 'package:models/unreadable_part.dart';
import 'package:models/upload_begun.dart';
import 'package:wyrm_client/wyrm_client.dart';

/// The answer of `restore_check` as `check_report` of `wyrm-admin` writes
/// it, with [over] laid over its fields (a null value removes the field).
Value _check([Map<String, Value?> over = const {}]) {
  final m = <String, Value?>{
    'size': const VInt(10573),
    'site': const VStr('plant'),
    'same_site': const VBool(true),
    'created': const VStr('2026-11-01T03:00:00Z'),
    'broker': const VStr('0.1.0'),
    'sealed': const VStr('passphrase'),
    'schemas': const VMap({
      'registry': VMap({'backup': VInt(19), 'here': VInt(20)}),
    }),
    'sections': const VMap({'control': VInt(1200), 'keys': VInt(48)}),
    'keys': const VStr('differ'),
    'keys_differ': const VArray([VStr('secrets.bin')]),
    'control_opens_here': const VBool(true),
    'links': const VMap({'modbus': VStr('exists'), 'new1': VStr('new')}),
    'problems': const VArray([]),
    'notes': const VArray([VStr('a note')]),
    'restart': const VStr('replace'),
    ...over,
  };
  return VMap({
    for (final e in m.entries) e.key: ?e.value,
  });
}

Invalid<T> _invalid<T>(Decoded<T> d) {
  expect(d, isA<Invalid<T>>());
  return d as Invalid<T>;
}

List<int> _json(Object? v) => utf8.encode(jsonEncode(v));

Map<String, Object?> _linkManifest([Map<String, Object?> over = const {}]) => {
  'wyrm_backup': 1,
  'kind': 'link',
  'site': 'plant',
  'broker': '0.1.0',
  'created': '2026-11-13T15:40:00Z',
  'schemas': <String, Object?>{},
  'sealed': {'how': 'broker'},
  'link': {
    'id': 'modbus',
    'driver': 'pkg:modbus',
    'mode': 'process',
    'package': 'modbus',
    'version': '0.5.0',
  },
  'sections': [
    {'name': 'settings', 'files': <Object>[]},
    {'name': 'package', 'files': <Object>[]},
  ],
  ...over,
};

/// The decoders of backups and restores (studio-rules §2, §8): each wire
/// answer decodes once into typed values; an answer of another shape and
/// a name this client does not know are refused with the field, never
/// read as a default.
void main() {
  group("the names are the broker's (wyrm-admin `SectionName`, "
      '`RestoreMode`)', () {
    test("sections, in the broker's order", () {
      expect(
        [for (final s in BackupSection.values) s.wire],
        [
          'control',
          'keys',
          'dataflows',
          'storage',
          'history',
          'links',
          'packages',
          'config',
          'settings',
          'data',
          'package',
        ],
      );
      expect(
        [for (final s in BackupSection.ofLink) s.wire],
        ['settings', 'data', 'package', 'history'],
      );
      expect(BackupSection.fromWire('flows'), isNull);
      expect(BackupSection.fromWire('Control'), isNull);
    });

    test('modes and what Studio sends for each (add: without the '
        'dataflows the broker skips)', () {
      expect([for (final m in RestoreMode.values) m.wire], ['add', 'replace']);
      expect(
        [for (final s in RestoreMode.add.sections) s.wire],
        ['links', 'storage'],
      );
      expect(
        [for (final s in RestoreMode.replace.sections) s.wire],
        [
          'control',
          'keys',
          'dataflows',
          'storage',
          'history',
          'links',
          'packages',
        ],
      );
      expect(RestoreMode.fromWire('merge'), isNull);
    });

    test('key comparisons, link states, restore ends', () {
      expect(
        [for (final k in RestoreKeys.values) k.wire],
        ['none', 'same', 'differ', 'other'],
      );
      expect(RestoreKeys.differ.foreign, isTrue);
      expect(RestoreKeys.other.foreign, isTrue);
      expect(RestoreKeys.same.foreign, isFalse);
      expect(RestoreKeys.none.foreign, isFalse);
      expect(
        [for (final s in RestoreLinkState.values) s.wire],
        ['new', 'exists'],
      );
      expect(
        [for (final e in RestoreEnd.values) e.wire],
        ['restore_applied', 'restore_failed'],
      );
      // Studio's own states are not wire names: there is none to read.
      expect(BackupStage.values, hasLength(10));
      expect(BackupPlace.values, hasLength(3));
    });
  });

  group('restore_check', () {
    test("the broker's answer, typed", () {
      expect(
        restoreCheckOf(_check()),
        Valid(
          RestoreCheck(
            site: 'plant',
            sameSite: true,
            created: DateTime.utc(2026, 11, 1, 3),
            broker: '0.1.0',
            sealed: BackupSealed.passphrase,
            schemas: const {
              'registry': SchemaPair(backup: 19, here: 20),
            }.lock,
            sections: const {
              BackupSection.control: 1200,
              BackupSection.keys: 48,
            }.lock,
            keys: RestoreKeys.differ,
            keysDiffer: const ['secrets.bin'].lock,
            links: const {
              'modbus': RestoreLinkState.exists,
              'new1': RestoreLinkState.fresh,
            }.lock,
            notes: const ['a note'].lock,
          ),
        ),
      );
    });

    test('an answer of another shape names what is wrong', () {
      expect(
        restoreCheckOf(const VStr('ok')),
        const Invalid<RestoreCheck>('restore check', '', 'not a map'),
      );
      expect(
        restoreCheckOf(const VNull()),
        const Invalid<RestoreCheck>('restore check', '', 'not a map'),
      );
      for (final (over, field, reason)
          in <(Map<String, Value?>, String, String)>[
            ({'site': null}, 'site', 'missing'),
            ({'same_site': const VStr('yes')}, 'same_site', 'not a bool'),
            ({'same_site': null}, 'same_site', 'missing'),
            (
              {'created': const VStr('yesterday')},
              'created',
              'not an ISO 8601 time',
            ),
            ({'sealed': null}, 'sealed', 'missing'),
            ({'keys': null}, 'keys', 'missing'),
            ({'keys': const VInt(1)}, 'keys', 'not a text'),
            (
              {'keys_differ': const VStr('secrets.bin')},
              'keys_differ',
              'not an array',
            ),
            ({'sections': const VArray([])}, 'sections', 'not a map'),
            (
              {
                'sections': const VMap({'control': VStr('big')}),
              },
              'sections',
              'not a whole number',
            ),
            (
              {
                'schemas': const VMap({'registry': VInt(19)}),
              },
              'schemas',
              'not a map',
            ),
            (
              {
                'schemas': const VMap({
                  'registry': VMap({'backup': VInt(19)}),
                }),
              },
              'here',
              'missing',
            ),
            ({'control_opens_here': null}, 'control_opens_here', 'missing'),
            ({'links': null}, 'links', 'missing'),
            ({'problems': null}, 'problems', 'missing'),
            (
              {
                'notes': const VArray([VInt(1)]),
              },
              'notes',
              'not texts',
            ),
          ]) {
        final i = _invalid(restoreCheckOf(_check(over)));
        expect((i.field, i.reason), (field, reason), reason: '$over');
      }
    });

    test('a name this client does not know is refused, not defaulted', () {
      for (final (over, field) in <(Map<String, Value?>, String)>[
        // a seal it does not know is not "none"
        ({'sealed': const VStr('hsm')}, 'sealed'),
        // a key comparison it does not know is not "none"
        ({'keys': const VStr('rotated')}, 'keys'),
        (
          {
            'sections': const VMap({'flows': VInt(1)}),
          },
          'sections',
        ),
        (
          {
            'links': const VMap({'modbus': VStr('older')}),
          },
          'links',
        ),
      ]) {
        final i = _invalid(restoreCheckOf(_check(over)));
        expect(i.field, field, reason: '$over');
        expect(i.reason, contains('not a known'), reason: '$over');
      }
    });
  });

  group('restore_apply', () {
    test('add: what it did and skipped', () {
      expect(
        restoreAnswerOf(
          const VMap({
            'mode': VStr('add'),
            'done': VArray([VStr('link new1')]),
            'skipped': VArray([VStr('link modbus: exists')]),
            'restart': VBool(false),
          }),
        ),
        Valid(
          RestoreAnswer(
            mode: RestoreMode.add,
            restart: false,
            done: const ['link new1'].lock,
            skipped: const ['link modbus: exists'].lock,
          ),
        ),
      );
    });

    test('replace: the sections staged, and the restart', () {
      expect(
        restoreAnswerOf(
          const VMap({
            'mode': VStr('replace'),
            'sections': VArray([VStr('control'), VStr('keys')]),
            'restart': VBool(true),
          }),
        ),
        Valid(
          RestoreAnswer(
            mode: RestoreMode.replace,
            restart: true,
            sections: const [BackupSection.control, BackupSection.keys].lock,
          ),
        ),
      );
    });

    test('another shape, an unknown mode or section: refused', () {
      for (final (answer, field, reason) in <(Value, String, String)>[
        (const VNull(), '', 'not a map'),
        (
          const VMap({'restart': VBool(true)}),
          'mode',
          'missing',
        ),
        (
          const VMap({'mode': VStr('merge'), 'restart': VBool(false)}),
          'mode',
          'not a known name',
        ),
        (
          const VMap({'mode': VStr('add')}),
          'restart',
          'missing',
        ),
        (
          const VMap({'mode': VStr('add'), 'restart': VStr('no')}),
          'restart',
          'not a bool',
        ),
        // `restart` goes with the mode: a restart is never guessed
        (
          const VMap({
            'mode': VStr('add'),
            'done': VArray([]),
            'skipped': VArray([]),
            'restart': VBool(true),
          }),
          'restart',
          'true for mode add',
        ),
        (
          const VMap({
            'mode': VStr('replace'),
            'sections': VArray([VStr('control')]),
            'restart': VBool(false),
          }),
          'restart',
          'false for mode replace',
        ),
        (
          const VMap({'mode': VStr('add'), 'restart': VBool(false)}),
          'done',
          'missing',
        ),
        (
          const VMap({
            'mode': VStr('replace'),
            'sections': VArray([VStr('control'), VStr('flows')]),
            'restart': VBool(true),
          }),
          'sections',
          'not a known name',
        ),
        (
          const VMap({
            'mode': VStr('replace'),
            'sections': VStr('control'),
            'restart': VBool(true),
          }),
          'sections',
          'not an array',
        ),
      ]) {
        final i = _invalid(restoreAnswerOf(answer));
        expect((i.field, i.reason), (field, reason), reason: '$answer');
      }
    });
  });

  group('the audit records of a staged restore', () {
    test('only the two restore ends, oldest first; `t` in µs', () {
      expect(
        restoreRecordsOf(
          const VArray([
            VMap({'t': VInt(1794100000000000), 'op': VStr('token_add')}),
            VMap({
              't': VInt(1794108760000000),
              'op': VStr('restore_failed'),
              'detail': VStr('registry: bad chain'),
            }),
            VMap({'t': VInt(1794108761500000), 'op': VStr('restore_applied')}),
          ]),
        ),
        const <Decoded<RestoreRecord?>>[
          Valid(null),
          Valid(
            RestoreRecord(
              end: RestoreEnd.failed,
              seconds: 1794108760,
              detail: 'registry: bad chain',
            ),
          ),
          Valid(RestoreRecord(end: RestoreEnd.applied, seconds: 1794108761)),
        ],
      );
      expect(restoreRecordsOf(const VArray([])), isEmpty);
    });

    test('a row of another shape is refused by itself, the others are '
        'read', () {
      expect(
        restoreRecordsOf(
          const VArray([
            VStr('restore_applied'),
            VMap({'t': VInt(1)}),
            VMap({'op': VStr('restore_applied')}),
            VMap({'op': VStr('restore_applied'), 't': VStr('now')}),
            VMap({
              'op': VStr('restore_failed'),
              't': VInt(1),
              'detail': VInt(2),
            }),
            VMap({'t': VInt(1794108761500000), 'op': VStr('restore_applied')}),
          ]),
        ),
        const <Decoded<RestoreRecord?>>[
          Invalid('restore record', '', 'not a map'),
          Invalid('restore record', 'op', 'missing'),
          Invalid('restore record', 't', 'missing'),
          Invalid('restore record', 't', 'not a whole number'),
          Invalid('restore record', 'detail', 'not a text'),
          Valid(RestoreRecord(end: RestoreEnd.applied, seconds: 1794108761)),
        ],
      );
    });

    test('an answer that is no array is refused whole', () {
      for (final rows in const <Value>[VNull(), VMap({})]) {
        expect(restoreRecordsOf(rows), const <Decoded<RestoreRecord?>>[
          Invalid('restore record', '', 'not an array'),
        ]);
      }
    });
  });

  group('estimate and create', () {
    test('the bytes of each section', () {
      expect(
        backupEstimateOf(
          const VMap({
            'sections': VMap({'control': VInt(1200), 'history': VFloat(5000)}),
            'total': VInt(6200),
          }),
        ),
        Valid(
          const {
            BackupSection.control: 1200,
            BackupSection.history: 5000,
          }.lock,
        ),
      );
    });

    test('another shape or an unknown section is refused', () {
      expect(_invalid(backupEstimateOf(const VNull())).reason, 'not a map');
      expect(
        _invalid(backupEstimateOf(const VMap({'total': VInt(1)}))).field,
        'sections',
      );
      expect(
        _invalid(
          backupEstimateOf(
            const VMap({
              'sections': VMap({'flows': VInt(1)}),
            }),
          ),
        ).reason,
        contains('not a known section'),
      );
      expect(
        _invalid(
          backupEstimateOf(
            const VMap({
              'sections': VMap({'control': VFloat(1.5)}),
            }),
          ),
        ).reason,
        'not a whole number',
      );
    });

    test('the id of the job', () {
      expect(backupIdOf(const VMap({'id': VStr('b2')})), const Valid('b2'));
      expect(_invalid(backupIdOf(const VNull())).reason, 'not a map');
      expect(_invalid(backupIdOf(const VMap({}))).reason, 'missing');
      expect(
        _invalid(backupIdOf(const VMap({'id': VInt(2)}))).reason,
        'not a text',
      );
      expect(
        _invalid(backupIdOf(const VMap({'id': VStr('')}))).reason,
        'empty',
      );
    });
  });

  group('a kept backup', () {
    NodeMeta meta(Map<String, Value> attr) => NodeMeta(attr: attr);

    test('a section it does not know refuses the backup', () {
      final i = _invalid(
        backupJobOf(
          'b1',
          meta({
            'sections': const VArray([VStr('control'), VStr('flows')]),
          }),
        ),
      );
      expect((i.field, i.reason), ('sections', 'not a known section'));
    });

    test('the sections sys/backups offers are the known ones', () {
      expect(
        _invalid(
          backupsAttrsOf(
            meta({
              'sections': const VArray([VStr('control'), VStr('flows')]),
            }),
          ),
        ).field,
        'sections',
      );
      expect(
        _invalid(
          backupsAttrsOf(meta({'sections': const VStr('control')})),
        ).field,
        'sections',
      );
      expect(
        _invalid(
          backupsAttrsOf(
            meta({
              'sections': const VArray([VInt(1)]),
            }),
          ),
        ).field,
        'sections',
      );
    });

    test('the live step: a section, the writing, nothing', () {
      final warned = <String>[];
      Logger.root.level = Level.ALL;
      final sub = decodeLog.onRecord.listen((r) => warned.add(r.message));
      addTearDown(sub.cancel);
      const j = BackupJob(
        id: 'b1',
        step: BackupStep.section(BackupSection.control),
      );
      BackupStep step(Object? v) =>
          backupLiveOf(j, (leaf) => leaf == 'step' ? v : null, 'b1').step;

      expect(step('storage'), const BackupStep.section(BackupSection.storage));
      expect(step('writing'), const BackupStep.writing());
      expect(step(''), const BackupStep.none());
      // no value yet: what the job holds stays
      expect(step(null), const BackupStep.section(BackupSection.control));
      expect(warned, isEmpty);
      // a step it does not know keeps the last one, and is logged
      expect(step('sealing'), const BackupStep.section(BackupSection.control));
      expect(step(7), const BackupStep.section(BackupSection.control));
      expect(warned, [
        'b1: backup.step: not a known step',
        'b1: backup.step: not a text',
      ]);
    });
  });

  group('a transfer in parts', () {
    test("restore_begin: the id and a part within the broker's limit", () {
      expect(
        uploadBegunOf(
          const VMap({
            'upload': VStr('u1'),
            'part_size': VInt(4096),
            'max_part': VInt(64),
          }),
        ),
        const Valid(UploadBegun(upload: 'u1', partSize: 64)),
      );
      for (final (answer, field, reason) in <(Value, String, String)>[
        (const VNull(), '', 'not a map'),
        (
          const VMap({'part_size': VInt(1), 'max_part': VInt(1)}),
          'upload',
          'missing',
        ),
        (
          const VMap({
            'upload': VStr(''),
            'part_size': VInt(1),
            'max_part': VInt(1),
          }),
          'upload',
          'empty',
        ),
        (
          const VMap({'upload': VStr('u1'), 'max_part': VInt(1)}),
          'part_size',
          'missing',
        ),
        (
          const VMap({'upload': VStr('u1'), 'part_size': VInt(1)}),
          'max_part',
          'missing',
        ),
        (
          const VMap({
            'upload': VStr('u1'),
            'part_size': VInt(0),
            'max_part': VInt(1),
          }),
          'part_size',
          'below one byte',
        ),
        (
          const VMap({
            'upload': VStr('u1'),
            'part_size': VStr('4 MiB'),
            'max_part': VInt(1),
          }),
          'part_size',
          'not a whole number',
        ),
      ]) {
        final i = _invalid(uploadBegunOf(answer));
        expect((i.field, i.reason), (field, reason), reason: '$answer');
      }
    });

    test('download_part: the bytes, the size and the end', () {
      final part = <String, Value>{
        'offset': const VInt(4),
        'size': const VInt(10),
        'eof': const VBool(false),
        'data': VBytes(Uint8List.fromList([1, 2, 3])),
      };
      expect(
        filePartOf(VMap(part), 4),
        Valid(
          FilePart(data: Uint8List.fromList([1, 2, 3]), size: 10, eof: false),
        ),
      );
      Map<String, Value> without(String field) => {
        for (final e in part.entries)
          if (e.key != field) e.key: e.value,
      };
      for (final (answer, field, reason) in <(Value, String, String)>[
        (const VNull(), '', 'not a map'),
        (VMap(without('data')), 'data', 'missing'),
        (VMap({...part, 'data': const VStr('AQID')}), 'data', 'not bytes'),
        (VMap(without('size')), 'size', 'missing'),
        // without `eof` the end is not guessed from an empty part
        (VMap(without('eof')), 'eof', 'missing'),
        (VMap(without('offset')), 'offset', 'missing'),
        (
          VMap({...part, 'offset': const VInt(0)}),
          'offset',
          'not the offset asked for',
        ),
      ]) {
        final i = _invalid(filePartOf(answer, 4));
        expect((i.field, i.reason), (field, reason), reason: '$answer');
      }
    });

    test('the digest of a backup', () {
      expect(backupDigestOf(const VStr('ab12')), const Valid<String?>('ab12'));
      expect(backupDigestOf(null), const Valid<String?>(null));
      expect(backupDigestOf(const VNull()), const Valid<String?>(null));
      expect(_invalid(backupDigestOf(const VInt(1))).field, 'sha256');
    });
  });

  group('the manifest of a link backup', () {
    ManifestProblem problemOf(BackupManifest m) {
      expect(m, isA<UnreadableBackupManifest>());
      return (m as UnreadableBackupManifest).problem;
    }

    test('read once, typed', () {
      final m = backupManifestOf(_json(_linkManifest()));
      expect(m, isA<LinkBackupManifest>());
      final link = m as LinkBackupManifest;
      expect(
        link.link,
        BackupLinkFacts(
          id: 'modbus',
          mode: LinkMode.process,
          driver: 'pkg:modbus',
          site: 'plant',
          broker: '0.1.0',
          created: DateTime.utc(2026, 11, 13, 15, 40),
        ),
      );
      expect(link.sealed, BackupSealed.broker);
      expect(link.sections, [BackupSection.settings, BackupSection.package]);
      expect(link.pretty, contains('"sealed": "broker"'));
      expect(link.pretty, isNot(contains('files')));
    });

    test('a broker backup is another kind, by its name', () {
      expect(
        backupManifestOf(_json(_linkManifest({'kind': 'broker'}))),
        const BackupManifest.other('broker'),
      );
    });

    test('bytes that are no manifest, and fields of another form', () {
      expect(
        problemOf(backupManifestOf(utf8.encode('PK'))).fault,
        ManifestFault.notJson,
      );
      expect(
        problemOf(backupManifestOf(_json(['manifest']))),
        const ManifestProblem(fault: ManifestFault.notObject),
      );
      for (final (over, field, fault)
          in <(Map<String, Object?>, String, ManifestFault)>[
            ({'kind': 7}, 'kind', ManifestFault.wrongForm),
            ({'link': null}, 'link', ManifestFault.missing),
            ({'link': 'modbus'}, 'link', ManifestFault.wrongForm),
            (
              {
                'link': {'driver': 'modbus', 'mode': 'process'},
              },
              'link.id',
              ManifestFault.missing,
            ),
            ({'sealed': null}, 'sealed', ManifestFault.missing),
            ({'sealed': 'broker'}, 'sealed', ManifestFault.wrongForm),
            ({'sections': 'settings'}, 'sections', ManifestFault.wrongForm),
            ({'sections': null}, 'sections', ManifestFault.missing),
            (
              {
                'sections': ['settings'],
              },
              'sections',
              ManifestFault.wrongForm,
            ),
            ({'wyrm_backup': '1'}, 'wyrm_backup', ManifestFault.wrongForm),
            ({'site': null}, 'site', ManifestFault.missing),
            // a time the file writes in no form Studio reads
            ({'created': 'yesterday'}, 'created', ManifestFault.wrongForm),
          ]) {
        final p = problemOf(backupManifestOf(_json(_linkManifest(over))));
        expect((p.field, p.fault), (field, fault), reason: '$over');
      }
    });

    test('a seal, a mode or a section it does not know is refused', () {
      for (final (over, field, found)
          in <(Map<String, Object?>, String, String)>[
            // never read as "no secrets in the file"
            (
              {
                'sealed': {'how': 'hsm'},
              },
              'sealed.how',
              'hsm',
            ),
            (
              {
                'link': {'id': 'm', 'driver': 'd', 'mode': 'container'},
              },
              'link.mode',
              'container',
            ),
            (
              {
                'sections': [
                  {'name': 'flows'},
                ],
              },
              'sections.name',
              'flows',
            ),
          ]) {
        expect(
          problemOf(backupManifestOf(_json(_linkManifest(over)))),
          ManifestProblem(
            fault: ManifestFault.unknownName,
            field: field,
            found: found,
          ),
          reason: '$over',
        );
      }
    });
  });

  group('the manifest of a package', () {
    PackageManifest read(Object? json) {
      final r = packageManifestOf(_json(json));
      expect(r, isA<PackageManifestWasRead>());
      return (r as PackageManifestWasRead).manifest;
    }

    test('each field with its type', () {
      final m = read({
        'name': 'acme',
        'version': '1.2.0',
        'wyrm_link': 1,
        'kind': 'process',
        'entries': {'linux-arm64': 'bin/acme', 'macos-arm64': 7},
        'colour': 'red',
      });
      expect(m.name, const Stated<String>.given('acme'));
      expect(m.protocol.orNull, 1);
      expect(m.kind.orNull, PackageKind.process);
      expect(m.entries, {'linux-arm64': 'bin/acme', 'macos-arm64': null}.lock);
      expect(m.entry, const Stated<String>.absent());
      expect(m.unknown, ['colour']);
      expect(m.rights, isEmpty);
      expect(m.rightsProblem, isNull);
    });

    test('a field of another type is told from an absent one', () {
      final m = read({
        'name': 7,
        'wyrm_link': '1',
        'kind': 'container',
        'entries': ['bin/acme'],
        'requester': 'all',
      });
      expect(m.name, const Stated<String>.wrong('7'));
      expect(m.name.orNull, isNull);
      expect(m.name.written, '7');
      expect(m.version, const Stated<String>.absent());
      expect(m.version.written, isNull);
      expect(m.protocol, const Stated<int>.wrong('"1"'));
      // a kind that is not one of the two is not a kind
      expect(m.kind, const Stated<PackageKind>.wrong('container'));
      expect(m.entries, isNull);
      // rights that cannot be read are a problem with their field, and
      // no rights are taken from them
      expect(m.rights, isEmpty);
      expect(
        m.rightsProblem,
        const ManifestProblem(
          fault: ManifestFault.wrongForm,
          field: 'requester',
        ),
      );
    });

    test('bytes that are not a JSON object', () {
      final notJson = packageManifestOf(utf8.encode('{'));
      expect(notJson, isA<PackageManifestUnreadable>());
      expect(
        (notJson as PackageManifestUnreadable).problem.fault,
        ManifestFault.notJson,
      );
      expect(
        packageManifestOf(_json([1, 2])),
        const PackageManifestRead.unreadable(
          ManifestProblem(fault: ManifestFault.notObject),
        ),
      );
    });
  });

  group('an answer a call cannot read', () {
    test('is a typed refusal the app words; the field is in the log', () {
      final warned = <String>[];
      Logger.root.level = Level.ALL;
      final sub = decodeLog.onRecord.listen((r) => warned.add(r.message));
      addTearDown(sub.cancel);

      expect(
        const Valid(3).orRefuse(
          key: 'wy/plant/sys/backups',
          call: const .named('create'),
        ),
        3,
      );
      expect(warned, isEmpty);
      try {
        restoreCheckOf(
          _check({'keys': const VStr('rotated')}),
        ).orRefuse(
          key: 'wy/plant/sys/backups',
          call: const .named('restore_check'),
        );
        fail('an unreadable answer must not pass');
      } on StudioException catch (e) {
        expect(e.error.kind, ErrorKind.broker);
        expect(e.error.hint, const ErrorHint.unreadable(UnreadablePart.answer));
        expect(e.error.call, const ErrorCall.named('restore_check'));
        expect(e.error.key, 'wy/plant/sys/backups');
        expect(e.error.site, 'plant');
        // business says nothing in words of its own
        expect(e.error.message, isEmpty);
      }
      expect(warned, [
        'restore_check on wy/plant/sys/backups: restore check.keys: not a known name',
      ]);
    });
  });
}
