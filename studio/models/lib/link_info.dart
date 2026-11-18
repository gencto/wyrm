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

/// The driver name of a link that runs a package: `pkg:<name>`
/// (`crates/wyrm-admin`, ADR 0011). The one place that knows the form.
const _packageDriver = 'pkg:';

/// The driver of a link that runs the package [name].
String packageDriverOf(String name) => '$_packageDriver$name';

extension LinkPackage on LinkInfo {
  /// The package this link runs, or null for a built-in driver.
  String? get packageName => driver.startsWith(_packageDriver)
      ? driver.substring(_packageDriver.length)
      : null;

  /// The link runs a package (not a built-in driver).
  bool get runsPackage => packageName != null;
}
