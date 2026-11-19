import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_section.dart';
import 'send_link.dart';

part 'backups_attrs.freezed.dart';

@freezed
abstract class BackupsAttrs with _$BackupsAttrs {
  /// The attributes of `sys/backups` (ADR 0048 §3.4): whether the host
  /// lets secrets out (`export_secrets`), the file-store links backups
  /// may go to (`send_links`), the sections a backup may hold
  /// (`sections`) and the days a backup is kept (`keep_days`).
  const factory BackupsAttrs({
    @Default(false) bool exportSecrets,
    @Default(IListConst([])) IList<SendLink> sendLinks,
    @Default(IListConst([])) IList<BackupSection> sections,
    @Default(7) int keepDays,
  }) = _BackupsAttrs;
}
