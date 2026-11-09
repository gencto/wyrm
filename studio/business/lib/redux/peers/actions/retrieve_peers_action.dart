import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_mode.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../../wyrm/mappers/peer_mapper.dart';
import '../../../wyrm/mappers/values.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Reads what the Sites map draws around the site on screen: its upstreams
/// (`sys/upstream/*` and their values), the brokers below it
/// (`downstream/*` of profile `wy:broker`) and the sites they relay, the
/// devices of its external links, and its platform upstreams (the
/// `uplink` link's entries). Quarantine entries come from
/// `RetrieveQuarantineAction`.
class RetrievePeersAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final root = site.root;
    final viewed = site.viewed;
    if (root == null || viewed == null) {
      return null;
    }
    final api = deps.wyrm;
    final peers = <Peer>[];

    final ups = await _children(api, '$root/sys/upstream');
    if (ups.isNotEmpty) {
      final values = await readValues(api, '$root/sys/upstream/*/*');
      final connected = number(
        await readValue(api, '$root/sys/upstream_connected'),
      );
      for (final u in ups) {
        final v = {
          for (final e in values.entries)
            if (e.key.startsWith('$root/sys/upstream/${u.name}/'))
              e.key.split('/').last: e.value,
        };
        peers.add(
          upstreamPeerOf(viewed, u.name, u.meta, values: v).copyWith(
            connected: (connected ?? 0) > 0 && (boolean(v['enabled']) ?? true),
          ),
        );
      }
    }

    final below = await _children(api, '$root/downstream');
    for (final c in below) {
      if (downstreamPeerOf(viewed, c) case final p?) {
        peers.add(p);
      } else if (c.name == 'uplink') {
        for (final pl in await _children(api, '$root/downstream/uplink')) {
          if (pl.name == 'stats') {
            continue;
          }
          peers.add(
            Peer(
              site: pl.name,
              kind: PeerKind.platform,
              parent: viewed,
              connected: true,
              platform: pl.meta.displayName ?? pl.name,
            ),
          );
        }
      }
    }
    for (final c in site.choices) {
      if (c.relation == 'downstream' && c.via != null && c.via != viewed) {
        peers.add(
          Peer(
            site: c.site,
            kind: PeerKind.relayed,
            parent: c.via,
            connected: true,
            via: [c.via!].lock,
          ),
        );
      }
    }
    for (final l in links.table.values) {
      if (l.mode == LinkMode.external) {
        peers.add(
          Peer(
            site: l.id,
            kind: PeerKind.device,
            parent: viewed,
            connected: l.state == 'connected',
            url: l.device,
          ),
        );
      }
    }
    return state.copyWith.peers(
      table: IMap<String, Peer>.fromValues(
        values: peers,
        keyMapper: (p) => '${p.kind.name}:${p.site}',
      ),
      view: [for (final p in peers) '${p.kind.name}:${p.site}'].lock,
    );
  }

  static Future<List<Child>> _children(WyrmApi api, String key) async {
    try {
      return await api.children(key);
    } on WyrmException {
      return const [];
    }
  }
}
