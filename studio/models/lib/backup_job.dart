import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_kind.dart';
import 'backup_sealed.dart';
import 'backup_section.dart';
import 'backup_status.dart';
import 'backup_step.dart';

part 'backup_job.freezed.dart';

@freezed
abstract class BackupJob with _$BackupJob {
  /// One backup of `sys/backups/<id>` (ADR 0048 §3.4): its attributes and
  /// the values that move while it is made or sent.
  const factory BackupJob({
    required String id,

    @Default(BackupKind.full) BackupKind kind,

    /// The file name.
    @Default('') String name,
    @Default(IListConst([])) IList<BackupSection> sections,

    /// How its secrets are sealed.
    @Default(BackupSealed.none) BackupSealed sealed,

    /// The link of a link backup.
    @Default('') String link,

    /// Who made it.
    @Default('') String by,

    @Default(BackupStatus.unknown) BackupStatus status,

    /// Percent.
    @Default(0) int progress,
    @Default(BackupStep.none()) BackupStep step,

    /// Bytes.
    @Default(0) int size,
    @Default('') String sha256,

    DateTime? created,
    DateTime? expires,
    @Default('') String error,
    @Default('') String sentTo,

    @Default(BackupSendStatus.none) BackupSendStatus sendStatus,
    @Default(0) int sendProgress,
    @Default('') String sendError,
  }) = _BackupJob;
}
