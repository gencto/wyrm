import 'package:freezed_annotation/freezed_annotation.dart';

part 'install_target.freezed.dart';

/// A broker a link can be installed on: the site on screen, or a site below
/// it whose upstream allows config.
@freezed
abstract class InstallTarget with _$InstallTarget {
  const factory InstallTarget({
    required String site,

    /// Its `sys/distribution` (`linux-aarch64`), when read. Whether the
    /// user may install on it is the rights check's, from the grants of
    /// now (selector `installTargetReason`), not kept here.
    String? host,
  }) = _InstallTarget;
}
