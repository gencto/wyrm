import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/link_origin.dart';
import 'package:models/link_state.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'live_values.dart';

const _shape = 'link';

/// The full `~meta` of `sys/links/<id>` (`wy:link-def`) as a [LinkInfo].
///
/// The admin's `view=list` sends no `attr`, so each link's meta is read on
/// its own. The state is a value of its own (`sys/links/<id>/state`,
/// [linkStateSampleOf]); [state] is it when known. An attribute of another
/// type, or a mode or an origin this client does not know, is [Invalid]
/// with its field.
Decoded<LinkInfo> linkInfoOf(String id, NodeMeta m, {LinkState? state}) {
  final texts = <String, String?>{};
  for (final f in [
    'driver',
    'mode',
    'package',
    'version',
    'source',
    'sha256',
    'device',
    'address',
    'cn',
    'origin',
  ]) {
    switch (m.attr?[f]) {
      case null || VNull():
        texts[f] = null;
      case VStr(:final v):
        texts[f] = v;
      default:
        return Invalid(_shape, f, 'not a text');
    }
  }
  final mode = switch (texts['mode']) {
    null => LinkMode.embedded,
    final w => LinkMode.fromWire(w),
  };
  if (mode == null) {
    return const Invalid(_shape, 'mode', 'not a known mode');
  }
  final origin = switch (texts['origin']) {
    null => LinkOrigin.config,
    final w => LinkOrigin.fromWire(w),
  };
  if (origin == null) {
    return const Invalid(_shape, 'origin', 'not a known origin');
  }
  return Valid(
    LinkInfo(
      id: id,
      driver: texts['driver'] ?? '',
      mode: mode,
      state: state ?? LinkState.installed,
      package: texts['package'],
      version: texts['version'],
      source: texts['source'],
      sha256: texts['sha256'],
      device: texts['device'] ?? texts['address'],
      certificateCn: texts['cn'],
      note: m.displayName,
      origin: origin,
    ),
  );
}

/// `attr.updates_available` of `sys/links` (ADR 0048 §1): how many links
/// run a package with a newer version; none from a broker before it.
Decoded<int> updatesAvailableOf(NodeMeta m) =>
    switch (m.attr?['updates_available']) {
      null || VNull() => const Valid(0),
      VInt(:final v) => Valid(v),
      _ => const Invalid('links', 'updates_available', 'not a whole number'),
    };
