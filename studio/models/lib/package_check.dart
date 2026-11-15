import 'package:freezed_annotation/freezed_annotation.dart';

import 'package_check_result.dart';

part 'package_check.freezed.dart';

@freezed
abstract class PackageCheck with _$PackageCheck {
  /// One check of a custom package (docs/links.md §4).
  const factory PackageCheck({
    required String title,
    @Default('') String detail,
    @Default(PackageCheckResult.ok) PackageCheckResult result,
  }) = _PackageCheck;
}
