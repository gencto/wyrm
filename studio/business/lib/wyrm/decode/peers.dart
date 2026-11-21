import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'decoded.dart';
import 'fields.dart';

/// The profile of a broker node under `downstream` and `upstream`.
const brokerProfile = 'wy:broker';

/// The site of a child of `wy/<site>/downstream` that is a broker
/// (`wy:broker`, `attr {root, site}`): its `attr.site`, or its node name
/// when the attribute is absent. Null for a child that is no broker; a
/// `site` that is not a text is [Invalid].
Decoded<String>? brokerSiteOf(Child child) =>
    child.meta.profileName != brokerProfile
    ? null
    : decoding(
        'downstream broker',
        () => Fields.attrs(child.meta).textOr('site') ?? child.name,
      );

/// A child of `wy/<site>/downstream` that is a broker, as a downstream
/// [Peer] of [parent] with the sites it relays (`attr.via`). Null for a
/// child that is no broker.
Decoded<Peer>? downstreamPeerOf(String parent, Child child) =>
    child.meta.profileName != brokerProfile
    ? null
    : decoding('downstream broker', () {
        final f = Fields.attrs(child.meta);
        return Peer(
          site: f.textOr('site') ?? child.name,
          kind: PeerKind.downstream,
          parent: parent,
          connected: true,
          via: f.listOr('via').lock,
        );
      });

/// The value `sys/upstream_connected`: how many upstreams the broker is
/// connected to, as "at least one". No value: none.
Decoded<bool> upstreamConnectedOf(Value? value) => switch (value) {
  null || VNull() => const Valid(false),
  VInt(:final v) => Valid(v > 0),
  VFloat(:final v) => Valid(v > 0),
  _ => const Invalid('sys', 'upstream_connected', 'not a number'),
};

/// The values of `sys/upstream/<name>` ([values], by leaf: `url`,
/// `status`, `enabled`, `allow_config`, `val_hz`; a leaf with no value yet
/// is read from the attribute of that name in [m]) as an upstream [Peer]
/// of [site]. `status` is the broker's own words. The peer is connected when
/// the broker has an upstream connection ([anyConnected]) and this one is
/// enabled. A leaf of another type is [Invalid] with its name.
Decoded<Peer> upstreamPeerOf(
  String site,
  String name,
  NodeMeta m,
  Map<String, Value> values, {
  required bool anyConnected,
}) => decoding('upstream', () {
  final f = Fields.values({...?m.attr, ...values});
  return Peer(
    site: name,
    kind: PeerKind.upstream,
    parent: site,
    connected: anyConnected && (f.flagOr('enabled') ?? true),
    url: f.textOr('url'),
    status: f.textOr('status'),
    allowConfig: f.flagOr('allow_config'),
    valHz: f.numberOr('val_hz'),
  );
});

/// The full `~meta` of `sys/quarantine/<node>` (`wy:quarantine`) as a
/// [QuarantineEntry]: `attr {kind, first_seen, key, via, from | addr,
/// held}`. `kind` is required and one of the broker's two: what waits
/// under another kind is not shown as a link (its Authorize differs), it
/// is [Invalid].
Decoded<QuarantineEntry> quarantineEntryOf(String node, NodeMeta m) =>
    decoding('quarantine entry', () {
      final f = Fields.attrs(m);
      final cn = m.displayName ?? node;
      final from = f.textOr('from') ?? f.textOr('addr');
      final firstSeen = f.timeOr('first_seen');
      final deauthorized = f.flagOr('held') ?? false;
      // read whatever the kind, so that one of another shape is refused
      // with its name; a link keeps neither (the broker sends them for a
      // broker's enrollment only)
      final via = f.listOr('via').lock;
      final key = f.textOr('key');
      return switch (f.name('kind', QuarantineKind.fromWire)) {
        QuarantineKind.link => QuarantineEntry.link(
          cn: cn,
          node: node,
          from: from,
          firstSeen: firstSeen,
          deauthorized: deauthorized,
        ),
        // only a broker relays sites and has a key to compare
        QuarantineKind.broker => QuarantineEntry.broker(
          cn: cn,
          node: node,
          from: from,
          firstSeen: firstSeen,
          via: via,
          key: key,
          deauthorized: deauthorized,
        ),
      };
    });
