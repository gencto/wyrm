import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/backup_sealed.dart';
import 'package:models/backup_section.dart';
import 'package:models/restore_answer.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_end.dart';
import 'package:models/restore_keys.dart';
import 'package:models/restore_link_state.dart';
import 'package:models/restore_mode.dart';
import 'package:models/restore_record.dart';
import 'package:models/schema_pair.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'fields.dart';

BackupSection _section(String wire, String field) =>
    BackupSection.fromWire(wire) ??
    (throw BadField(field, 'not a known section: $wire'));

/// The answer of `sys/backups` ▸ `restore_check` (ADR 0048 §3.6,
/// `check_report` of `wyrm-admin`) as a [RestoreCheck]. Every field the
/// broker writes is required and of its type: a restore is decided on
/// this answer, so a section, a seal, a key comparison or a link state
/// this client does not know is [Invalid] with its field, never a default.
Decoded<RestoreCheck> restoreCheckOf(Value answer) =>
    decoding('restore check', () {
      final f = Fields.of(answer);
      return RestoreCheck(
        site: f.text('site'),
        sameSite: f.flag('same_site'),
        created: f.moment('created'),
        broker: f.text('broker'),
        sealed: f.name('sealed', BackupSealed.fromWire),
        schemas: {
          for (final e in f.map('schemas').entries)
            e.key: switch (Fields.of(e.value, 'schemas')) {
              final pair => SchemaPair(
                backup: pair.whole('backup'),
                here: pair.whole('here'),
              ),
            },
        }.lock,
        sections: {
          for (final e in f.map('sections').entries)
            _section(e.key, 'sections'): wholeOf(e.value, 'sections'),
        }.lock,
        keys: f.name('keys', RestoreKeys.fromWire),
        keysDiffer: f.texts('keys_differ').lock,
        controlOpensHere: f.flag('control_opens_here'),
        links: {
          for (final e in f.map('links').entries)
            e.key:
                RestoreLinkState.fromWire(textOf(e.value, 'links')) ??
                (throw const BadField('links', 'not a known state')),
        }.lock,
        problems: f.texts('problems').lock,
        notes: f.texts('notes').lock,
      );
    });

/// The answer of `sys/backups` ▸ `restore_apply`: `{mode: add, done,
/// skipped, restart: false}` or `{mode: replace, sections, restart: true}`.
/// A mode or a section this client does not know, or a `restart` that
/// does not go with the mode, is [Invalid].
Decoded<RestoreAnswer> restoreAnswerOf(Value answer) =>
    decoding('restore answer', () {
      final f = Fields.of(answer);
      final mode = f.name('mode', RestoreMode.fromWire);
      final restart = f.flag('restart');
      switch (mode) {
        case RestoreMode.add:
          if (restart) {
            throw const BadField('restart', 'true for mode add');
          }
          return RestoreAnswer(
            mode: mode,
            restart: false,
            done: f.texts('done').lock,
            skipped: f.texts('skipped').lock,
          );
        case RestoreMode.replace:
          if (!restart) {
            throw const BadField('restart', 'false for mode replace');
          }
          return RestoreAnswer(
            mode: mode,
            restart: true,
            sections: f.names('sections', BackupSection.fromWire).lock,
          );
      }
    });

/// The records of `sys/audit` ▸ `tail` that say how a staged restore
/// ended (`op` `restore_applied` or `restore_failed`), in the broker's
/// order (oldest first); `t` is µs since the epoch. Each row is read on
/// its own, so one row of another shape does not hide the others: a
/// record of another operation is a valid null, a row that is no record
/// (or a restore record without its time) is [Invalid]. An answer that is
/// no array is one [Invalid].
List<Decoded<RestoreRecord?>> restoreRecordsOf(Value rows) => switch (rows) {
  VArray(:final v) => [
    for (final r in v)
      decoding('restore record', () {
        final f = Fields.of(r);
        final end = RestoreEnd.fromWire(f.text('op'));
        return end == null
            ? null
            : RestoreRecord(
                end: end,
                seconds: f.whole('t') ~/ Duration.microsecondsPerSecond,
                detail: f.textOr('detail'),
              );
      }),
  ],
  _ => const [Invalid('restore record', '', 'not an array')],
};

/// The answer of `sys/backups` ▸ `estimate`: `{sections: {name: bytes},
/// total}`, as the bytes of each section.
Decoded<IMap<BackupSection, int>> backupEstimateOf(Value answer) =>
    decoding('backup estimate', () {
      final f = Fields.of(answer);
      return {
        for (final e in f.map('sections').entries)
          _section(e.key, 'sections'): wholeOf(e.value, 'sections'),
      }.lock;
    });

/// The answer of `create` and of a link's `backup`: `{id}`, the job in
/// `sys/backups`.
Decoded<String> backupIdOf(Value answer) => decoding('backup id', () {
  final id = Fields.of(answer).text('id');
  return id.isEmpty ? (throw const BadField('id', 'empty')) : id;
});
