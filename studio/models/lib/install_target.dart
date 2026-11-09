import 'package:freezed_annotation/freezed_annotation.dart';

part 'install_target.freezed.dart';

/// A broker a link can be installed on: the site on screen, or a site below
/// it whose upstream allows config.
@freezed
abstract class InstallTarget with _$InstallTarget {
  const factory InstallTarget({
    required String site,

    /// `this broker` or `downstream`.
    @Default('this broker') String role,

    /// Its `sys/distribution` (`linux-aarch64`), when read.
    String? host,

    /// Why it cannot take the link; null when it can.
    String? refused,
  }) = _InstallTarget;
}
