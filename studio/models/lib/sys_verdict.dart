import 'package:freezed_annotation/freezed_annotation.dart';

part 'sys_verdict.freezed.dart';

/// What a broker action of `sys` answers when it says whether it did its
/// work (`install*`, `update`, `rollback`: `{success, message}`): its
/// verdict and its own words, kept verbatim.
@freezed
abstract class SysVerdict with _$SysVerdict {
  const factory SysVerdict({
    required bool success,
    String? message,

    /// The status of a refusal by its wire name (`timeout`), when the call
    /// was refused instead of answered; the screen writes it before the
    /// message.
    String? status,
  }) = _SysVerdict;
}
