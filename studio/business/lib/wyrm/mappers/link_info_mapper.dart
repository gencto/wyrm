import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The full `~meta` of `sys/links/<id>` (`wy:link-def`) as a [LinkInfo].
///
/// The admin's `view=list` sends no `attr`, so each link's meta is read on
/// its own. The state is a value of its own (`sys/links/<id>/state`, an enum
/// code, [linkStateOf]); [state] is it when known.
LinkInfo linkInfoOf(String id, NodeMeta m, {String? state}) => LinkInfo(
  id: id,
  driver: str(attrOf(m, 'driver')) ?? '',
  mode: linkModeOf(str(attrOf(m, 'mode'))),
  state: state ?? 'installed',
  package: str(attrOf(m, 'package')),
  version: str(attrOf(m, 'version')),
  source: str(attrOf(m, 'source')),
  sha256: str(attrOf(m, 'sha256')),
  device: str(attrOf(m, 'device')) ?? str(attrOf(m, 'address')),
  certificateCn: str(attrOf(m, 'cn')),
  note: m.displayName,
  origin: str(attrOf(m, 'origin')) ?? 'config',
);

/// `attr.mode` of a link: `embedded`, `process`, `wasm`, `external`.
///
/// A `pkg:<name>` driver whose mode is embedded runs a WASM component.
LinkMode linkModeOf(String? mode) => switch (mode) {
  'process' => LinkMode.process,
  'wasm' => LinkMode.wasm,
  'external' => LinkMode.external,
  _ => LinkMode.embedded,
};

/// The states of `sys/links/<id>/state`, by enum code (wyrm-admin `STATES`).
const linkStates = [
  'installed',
  'starting',
  'connected',
  'stopping',
  'stopped',
  'failed',
];

/// A `state` sample (an enum code, or a name) as its name.
String linkStateOf(Object? v) => switch (v) {
  final int i when i >= 0 && i < linkStates.length => linkStates[i],
  final String s => s,
  _ => 'installed',
};
