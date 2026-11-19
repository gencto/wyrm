import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_section.dart';
import 'restore_mode.dart';

part 'restore_answer.freezed.dart';

@freezed
abstract class RestoreAnswer with _$RestoreAnswer {
  /// The answer of `sys/backups` ▸ `restore_apply` (ADR 0048 §3.6): an
  /// `add` says what it did and skipped; a `replace` the sections it
  /// staged, and the broker restarts.
  const factory RestoreAnswer({
    required RestoreMode mode,
    required bool restart,

    /// The sections staged (`replace`).
    @Default(IListConst([])) IList<BackupSection> sections,

    /// What was added, in the broker's words (`add`).
    @Default(IListConst([])) IList<String> done,

    /// What was left as it is, with the reason (`add`).
    @Default(IListConst([])) IList<String> skipped,
  }) = _RestoreAnswer;
}
