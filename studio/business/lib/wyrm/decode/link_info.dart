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
/// [linkStateSampleOf]); [state] is it when known. Each attribute is
/// decoded on its own: one of another type, or a mode or an origin this
/// client does not know, is left at its default **and logged** with its
/// field and [where]; the others stay.
LinkInfo linkInfoOf(
  String id,
  NodeMeta m, {
  required String where,
  LinkState? state,
}) {
  String? text(String f) => attrText(m, f).orWarn(where);
  E? named<E>(String f, E? Function(String) fromWire) => switch (text(f)) {
    null => null,
    final w => switch (fromWire(w)) {
      final e? => e,
      null => Invalid<E>(_shape, f, 'not a known name').orWarn(where),
    },
  };
  return LinkInfo(
    id: id,
    driver: text('driver') ?? '',
    mode: named('mode', LinkMode.fromWire) ?? LinkMode.embedded,
    state: state ?? LinkState.installed,
    package: text('package'),
    version: text('version'),
    source: text('source'),
    sha256: text('sha256'),
    device: text('device') ?? text('address'),
    certificateCn: text('cn'),
    note: m.displayName,
    origin: named('origin', LinkOrigin.fromWire) ?? LinkOrigin.config,
  );
}

/// The text attribute [field] of [m]: none when absent; [Invalid] when it
/// is not a text.
Decoded<String?> attrText(NodeMeta m, String field) => switch (m.attr?[field]) {
  null || VNull() => const Valid(null),
  VStr(:final v) => Valid(v),
  _ => Invalid(_shape, field, 'not a text'),
};

/// `attr.updates_available` of `sys/links` (ADR 0048 §1): how many links
/// run a package with a newer version; none from a broker before it.
Decoded<int> updatesAvailableOf(NodeMeta m) =>
    switch (m.attr?['updates_available']) {
      null || VNull() => const Valid(0),
      VInt(:final v) => Valid(v),
      _ => const Invalid('links', 'updates_available', 'not a whole number'),
    };
