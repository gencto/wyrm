import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The full `~meta` of `sys/quarantine/<node>` (`wy:quarantine`) as a
/// [QuarantineEntry].
QuarantineEntry quarantineEntryOf(String node, NodeMeta m) => QuarantineEntry(
  cn: m.displayName ?? node,
  node: node,
  // a kind this client does not know waits as a link, as before it was
  // typed
  kind: switch (str(attrOf(m, 'kind'))) {
    null => QuarantineKind.link,
    final k => QuarantineKind.fromWire(k) ?? QuarantineKind.link,
  },
  from: str(attrOf(m, 'from')) ?? str(attrOf(m, 'addr')),
  firstSeen: time(attrOf(m, 'first_seen')),
  via: strings(attrOf(m, 'via')).lock,
  key: str(attrOf(m, 'key')),
  deauthorized: boolean(attrOf(m, 'held')) ?? false,
);
