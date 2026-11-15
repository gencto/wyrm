import 'package:freezed_annotation/freezed_annotation.dart';

import 'link_mode.dart';
import 'link_origin.dart';
import 'link_state.dart';

part 'link_info.freezed.dart';

@freezed
abstract class LinkInfo with _$LinkInfo {
  /// One link of `sys/links`.
  const factory LinkInfo({
    required String id,
    @Default('') String driver,
    @Default(LinkMode.embedded) LinkMode mode,

    @Default(LinkState.installed) LinkState state,
    String? package,
    String? version,
    String? source,
    String? sha256,

    /// External links: the device address.
    String? device,
    String? certificateCn,
    String? note,

    @Default(LinkOrigin.config) LinkOrigin origin,
  }) = _LinkInfo;
}
