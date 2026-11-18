import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/backup_job.dart';
import 'package:models/backup_place.dart';
import 'package:models/backup_section.dart';
import 'package:models/backup_stage.dart';
import 'package:models/backups_read.dart';
import 'package:models/restore_check.dart';
import 'package:models/restore_mode.dart';
import 'package:models/send_link.dart';

part 'backups_state.freezed.dart';

@freezed
abstract class BackupsState with _$BackupsState {
  const factory BackupsState({
    @Default(IMapConst({})) IMap<String, BackupJob> table,
    @Default(IListConst([])) IList<String> view,
    @Default(false) bool exportSecrets,
    @Default(IListConst([])) IList<SendLink> sendLinks,
    @Default(IListConst([])) IList<BackupSection> sections,
    @Default(7) int keepDays,
    BackupStage? stage,

    /// Counts the dialogs opened: a read started for one is dropped when it
    /// ends under another (or none).
    @Default(0) int opening,
    String? link,
    @Default(ISetConst({})) ISet<BackupSection> chosen,
    int? historyDays,
    @Default(ISetConst({})) ISet<String> offLinks,
    @Default(BackupPlace.computer) BackupPlace where,
    String? sendLink,
    String? sendConnection,
    String? sendPath,
    @Default(IListConst([])) IList<String> connections,
    @Default(IMapConst({})) IMap<BackupSection, int> estimate,
    String? job,
    String? downloading,
    @Default(0) int downloaded,
    String? upload,
    String? uploadName,
    @Default(0) int uploadSize,
    @Default(0) int uploaded,
    RestoreCheck? check,
    @Default(RestoreMode.add) RestoreMode mode,
    @Default(false) bool replaceKeys,
    @Default(false) bool acceptRights,
    String? result,
    @Default(IMapConst({})) IMap<String, String> saved,
    @Default(IListConst([])) IList<BackupSection> staged,
    @Default(BackupsRead.absent) BackupsRead availability,
    @Default(IListConst([])) IList<String> unread,
  }) = _BackupsState;
}
