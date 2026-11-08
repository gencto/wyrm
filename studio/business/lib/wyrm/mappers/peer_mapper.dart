import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'values.dart';

/// A child of `wy/<site>/downstream` that is a broker (`wy:broker`,
/// `attr {root, site}`), as a downstream [Peer] of [parent].
Peer? downstreamPeerOf(String parent, Child child) {
  final m = child.meta;
  if (m.profileName != 'wy:broker') {
    return null;
  }
  return Peer(
    site: str(attrOf(m, 'site')) ?? child.name,
    kind: PeerKind.downstream,
    parent: parent,
    connected: true,
    via: strings(attrOf(m, 'via')).lock,
  );
}

/// The full `~meta` of `sys/upstream/<name>` and its values as an upstream
/// [Peer] of [site].
Peer upstreamPeerOf(
  String site,
  String name,
  NodeMeta m, {
  Map<String, Value> values = const {},
}) => Peer(
  site: name,
  kind: PeerKind.upstream,
  parent: site,
  connected:
      boolean(values['connected']) ??
      (str(values['status']) ?? str(attrOf(m, 'status'))) == 'connected',
  url: str(values['url']) ?? str(attrOf(m, 'url')),
  status: str(values['status']) ?? str(attrOf(m, 'status')),
  allowConfig:
      boolean(values['allow_config']) ?? boolean(attrOf(m, 'allow_config')),
  valHz: number(values['val_hz']) ?? number(attrOf(m, 'val_hz')),
);
