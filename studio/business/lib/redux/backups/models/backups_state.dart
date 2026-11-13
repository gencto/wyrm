import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:models/backup_job.dart';
import 'package:models/restore_check.dart';
import 'package:models/send_link.dart';

part 'backups_state.freezed.dart';

@freezed
abstract class BackupsState with _$BackupsState {
  const factory BackupsState({
    @Default(IMapConst({})) IMap<String, BackupJob> table,
    @Default(IListConst([])) IList<String> view,
    @Default(false) bool exportSecrets,
    @Default(IListConst([])) IList<SendLink> sendLinks,
    @Default(IListConst([])) IList<String> sections,
    @Default(7) int keepDays,
    String? stage,
    String? link,
    @Default(ISetConst({})) ISet<String> chosen,
    int? historyDays,
    @Default(ISetConst({})) ISet<String> offLinks,
    @Default('computer') String where,
    String? sendLink,
    String? sendConnection,
    String? sendPath,
    @Default(IListConst([])) IList<String> connections,
    @Default(IMapConst({})) IMap<String, int> estimate,
    String? job,
    String? downloading,
    @Default(0) int downloaded,
    String? upload,
    String? uploadName,
    @Default(0) int uploadSize,
    @Default(0) int uploaded,
    RestoreCheck? check,
    @Default('add') String mode,
    @Default(false) bool replaceKeys,
    @Default(false) bool acceptRights,
    String? result,
    @Default(IMapConst({})) IMap<String, String> saved,
  }) = _BackupsState;
}
