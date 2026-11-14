import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'backup_job.freezed.dart';

@freezed
abstract class BackupJob with _$BackupJob {
  /// One backup of `sys/backups/<id>` (ADR 0048 §3.4): its attributes and
  /// the values that move while it is made or sent.
  const factory BackupJob({
    required String id,

    /// `full`, `link`, `pre-update` or `pre-restore`.
    @Default('full') String kind,

    /// The file name.
    @Default('') String name,
    @Default(IListConst([])) IList<String> sections,

    /// How its secrets are sealed: `none`, `passphrase` or `broker`.
    @Default('none') String sealed,

    /// The link of a link backup.
    @Default('') String link,

    /// Who made it.
    @Default('') String by,

    /// `running`, `done` or `failed`.
    @Default('') String status,

    /// Percent.
    @Default(0) int progress,
    @Default('') String step,

    /// Bytes.
    @Default(0) int size,
    @Default('') String sha256,

    /// ISO 8601, UTC.
    @Default('') String created,
    @Default('') String expires,
    @Default('') String error,
    @Default('') String sentTo,

    /// `sending`, `done` or `failed`; empty when never sent.
    @Default('') String sendStatus,
    @Default(0) int sendProgress,
    @Default('') String sendError,
  }) = _BackupJob;
}
