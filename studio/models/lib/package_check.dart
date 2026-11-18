import 'package:freezed_annotation/freezed_annotation.dart';

import 'package_check_result.dart';
import 'package_finding.dart';

part 'package_check.freezed.dart';

@freezed
abstract class PackageCheck with _$PackageCheck {
  /// One check of a custom package or a link backup (docs/links.md §4):
  /// what it found, as facts, and whether that passes. `ui` names the
  /// check and says the finding.
  const factory PackageCheck(
    PackageFinding finding, {
    @Default(PackageCheckResult.ok) PackageCheckResult result,
  }) = _PackageCheck;
}
