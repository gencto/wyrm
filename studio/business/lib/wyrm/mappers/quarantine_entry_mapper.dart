import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/quarantine_entry.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// The full `~meta` of `sys/quarantine/<node>` (`wy:quarantine`) as a
/// [QuarantineEntry].
QuarantineEntry quarantineEntryOf(String node, NodeMeta m) => QuarantineEntry(
  cn: m.displayName ?? node,
  node: node,
  kind: str(attrOf(m, 'kind')) ?? 'link',
  from: str(attrOf(m, 'from')) ?? str(attrOf(m, 'addr')),
  firstSeen: time(attrOf(m, 'first_seen')),
  via: strings(attrOf(m, 'via')).lock,
  key: str(attrOf(m, 'key')),
  deauthorized: boolean(attrOf(m, 'held')) ?? false,
);
