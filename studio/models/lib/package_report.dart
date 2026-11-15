import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_mode.dart';
import 'package_check.dart';
import 'requested_right.dart';

part 'package_report.freezed.dart';

/// What the check of a custom package or a link backup found
/// (docs/links.md §4): the checks, the manifest as indented JSON, the
/// package's name and how it runs from it, and the rights it asks for
/// (null: none asked, or not read).
@freezed
abstract class PackageReport with _$PackageReport {
  const factory PackageReport({
    required IList<PackageCheck> checks,
    String? manifest,
    String? name,
    LinkMode? kind,
    IList<RequestedRight>? rights,
  }) = _PackageReport;
}
