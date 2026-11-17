import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'backup_link_facts.dart';
import 'manifest_problem.dart';
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

    /// What is wrong with the manifest [file], when the check is of it:
    /// ui words it ([detail] is then empty).
    ManifestProblem? problem,

    /// The manifest the [problem] is of, by its name in the archive.
    String? file,

    /// The link of a link backup, when the check shows it: ui words it
    /// ([detail] is then empty).
    BackupLinkFacts? link,
  }) = _PackageCheck;
}
