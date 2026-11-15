import 'package:freezed_annotation/freezed_annotation.dart';

part 'audit_line.freezed.dart';

/// One record of the audit tail (`sys/audit ▸ tail`), as Access lists it:
/// when, who, what was done (the operation, its key, its action) and what
/// came of it, each as the broker wrote it; empty when it wrote none.
@freezed
abstract class AuditLine with _$AuditLine {
  const factory AuditLine({
    @Default('') String time,
    @Default('') String who,
    @Default('') String what,
    @Default('') String result,
  }) = _AuditLine;
}
