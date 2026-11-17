import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_sealed.dart';
import 'backup_section.dart';
import 'restore_keys.dart';
import 'restore_link_state.dart';
import 'schema_pair.dart';

part 'restore_check.freezed.dart';

@freezed
abstract class RestoreCheck with _$RestoreCheck {
  /// The answer of `sys/backups` ▸ `restore_check` (ADR 0048 §3.6).
  const factory RestoreCheck({
    @Default('') String site,
    @Default(false) bool sameSite,

    /// When the backup was made.
    DateTime? created,
    @Default('') String broker,

    /// How the secrets of the file are sealed.
    @Default(BackupSealed.none) BackupSealed sealed,

    /// Store SCHEMA by store: in the backup and here.
    @Default(IMapConst({})) IMap<String, SchemaPair> schemas,

    /// The sections of the file with their bytes.
    @Default(IMapConst({})) IMap<BackupSection, int> sections,

    /// How the keys of the file compare with this broker's.
    @Default(RestoreKeys.none) RestoreKeys keys,

    /// The key files that are not this broker's.
    @Default(IListConst([])) IList<String> keysDiffer,
    @Default(true) bool controlOpensHere,

    /// Each link of the file against this broker.
    @Default(IMapConst({})) IMap<String, RestoreLinkState> links,

    /// Each blocks `replace`.
    @Default(IListConst([])) IList<String> problems,
    @Default(IListConst([])) IList<String> notes,
  }) = _RestoreCheck;
}
