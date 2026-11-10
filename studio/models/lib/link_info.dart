import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_mode.dart';

part 'link_info.freezed.dart';

@freezed
abstract class LinkInfo with _$LinkInfo {
  /// One link of `sys/links`.
  const factory LinkInfo({
    required String id,
    @Default('') String driver,
    @Default(LinkMode.embedded) LinkMode mode,

    /// installed, starting, connected, stopping, stopped, failed.
    @Default('installed') String state,
    String? package,
    String? version,
    String? source,
    String? sha256,

    /// External links: the device address.
    String? device,
    String? certificateCn,
    String? note,

    /// `config` (from `wyrmd.json5`) or `runtime` (installed or admitted
    /// while the broker runs).
    @Default('config') String origin,
  }) = _LinkInfo;
}
