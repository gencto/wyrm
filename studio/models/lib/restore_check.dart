import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'restore_check.freezed.dart';

@freezed
abstract class RestoreCheck with _$RestoreCheck {
  /// The answer of `sys/backups` ▸ `restore_check` (ADR 0048 §3.6).
  const factory RestoreCheck({
    @Default('') String site,
    @Default(false) bool sameSite,
    @Default('') String created,
    @Default('') String broker,

    /// `none`, `passphrase` or `broker`.
    @Default('none') String sealed,

    /// Store SCHEMA by store: `(backup, here)`.
    @Default(IMapConst({})) IMap<String, (int, int)> schemas,

    /// The sections of the file with their bytes.
    @Default(IMapConst({})) IMap<String, int> sections,

    /// `none`, `same`, `differ` or `other`.
    @Default('none') String keys,

    /// The key files that are not this broker's.
    @Default(IListConst([])) IList<String> keysDiffer,
    @Default(true) bool controlOpensHere,

    /// Each link of the file: `new` or `exists`.
    @Default(IMapConst({})) IMap<String, String> links,

    /// Each blocks `replace`.
    @Default(IListConst([])) IList<String> problems,
    @Default(IListConst([])) IList<String> notes,
  }) = _RestoreCheck;
}
