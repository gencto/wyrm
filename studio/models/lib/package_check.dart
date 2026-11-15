import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package_check_result.dart';
import 'requested_right.dart';

part 'package_check.freezed.dart';

@freezed
abstract class PackageCheck with _$PackageCheck {
  /// One check of a custom package (docs/links.md §4).
  const factory PackageCheck({
    required String title,
    @Default('') String detail,
    @Default(PackageCheckResult.ok) PackageCheckResult result,

    /// The rights the package asks for, when the check lists them (ui
    /// words them; [detail] is then empty).
    IList<RequestedRight>? rights,
  }) = _PackageCheck;
}
