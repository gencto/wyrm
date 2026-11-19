import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_section.dart';

part 'backup_step.freezed.dart';

/// What the making of a backup is at (`sys/backups/<id>/step`): nothing
/// yet, one of its sections, or the writing of the file.
@freezed
sealed class BackupStep with _$BackupStep {
  /// No step has arrived, or the backup is made.
  const factory BackupStep.none() = BackupStepNone;

  /// The section being copied.
  const factory BackupStep.section(BackupSection section) = BackupStepSection;

  /// Every section is copied: the file is written (`writing`).
  const factory BackupStep.writing() = BackupStepWriting;
}
