import 'package:freezed_annotation/freezed_annotation.dart';

part 'audit_entry.freezed.dart';

/// One record of `sys/audit` ▸ `tail`: a `set` or an `invoke` a link
/// checked, or a login (Explorer › Audit, filtered by the node's key).
@freezed
abstract class AuditEntry with _$AuditEntry {
  const factory AuditEntry({
    required DateTime time,

    /// `set`, `invoke`, `login`, …
    required String op,

    /// The key it was on (`…/~set`, `…/~act/<a>`).
    required String key,

    /// Who did it (`user:admin`, `claimed:flow:<id>`).
    required String who,

    /// 0 = done; else the refusal's status code.
    @Default(0) int status,
  }) = _AuditEntry;
}
