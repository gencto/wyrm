import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/link_state.dart';
import 'package:models/param_spec.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/quarantine_kind.dart';
import 'package:models/site_node.dart';
import 'package:models/site_pick.dart';
import 'package:wyrm_client/wyrm_client.dart' show Perm;

import '../redux/app_state.dart';
import 'rights.dart';

/// One node of the Sites map, with what its line says: a peer's [status]
/// or [detail] (a platform's kind, a device's address, the site a relayed
/// one comes through) and a [count] (the sites a broker below relays, the
/// relays of a waiting broker).
final class SiteMapNode {
  const SiteMapNode({
    required this.pick,
    required this.name,
    this.parent,
    this.offline = false,
    this.connected = false,
    this.status,
    this.detail,
    this.count = 0,
    this.waitingBroker = false,
    this.selected = false,
  });

  final SitePick pick;
  final String name;

  /// The node it hangs from; null for the top row.
  final SitePick? parent;
  final bool offline;
  final bool connected;
  final String? status;
  final String? detail;
  final int count;

  /// A waiting node is a broker (else a link).
  final bool waitingBroker;

  /// The node picked.
  final bool selected;

  SiteMapNode _picked(SitePick p) => SiteMapNode(
    pick: pick,
    name: name,
    parent: parent,
    offline: offline,
    connected: connected,
    status: status,
    detail: detail,
    count: count,
    waitingBroker: waitingBroker,
    selected: pick == p,
  );
}

/// What the inspector of Sites shows for the node picked.
sealed class SiteDetail {
  const SiteDetail(this.name, this.key);

  final String name;

  /// The node it is about, as the inspector writes it under its title.
  final String key;
}

/// This broker: its upstreams, the brokers and devices below, its version.
final class SelfDetail extends SiteDetail {
  const SelfDetail(
    super.name,
    super.key, {
    required this.connected,
    required this.upstreams,
    required this.below,
    required this.devices,
    this.version,
  });

  final bool connected;
  final List<String> upstreams;
  final int below;
  final int devices;
  final String? version;
}

/// An upstream broker, as `sys/upstream/<name>` says it.
final class UpstreamDetail extends SiteDetail {
  const UpstreamDetail(
    super.name,
    super.key, {
    required this.connected,
    this.url,
    this.status,
    this.allowConfig,
  });

  final bool connected;
  final String? url;
  final String? status;
  final bool? allowConfig;
}

/// A broker below and the sites it relays.
final class DownstreamDetail extends SiteDetail {
  const DownstreamDetail(super.name, super.key, {required this.relays});

  final int relays;
}

/// A connection that waits in quarantine, with the form of its `approve`
/// when it is a broker.
final class WaitingDetail extends SiteDetail {
  const WaitingDetail(super.name, super.key, {required this.entry, this.form});

  final QuarantineEntry entry;
  final IList<ParamSpec>? form;
}

/// A device of an external link.
final class DeviceDetail extends SiteDetail {
  const DeviceDetail(
    super.name,
    super.key, {
    required this.connected,
    required this.branch,
    this.device,
  });

  final bool connected;
  final String branch;
  final String? device;
}

/// A site relayed below, and the broker it comes through.
final class RelayedDetail extends SiteDetail {
  const RelayedDetail(super.name, super.key, {required this.through});

  final String through;
}

/// A platform the site sends to through the `uplink` link.
final class PlatformDetail extends SiteDetail {
  const PlatformDetail(super.name, super.key, {this.platform});

  final String? platform;
}

/// What Sites shows, computed from the state.
final class _Sites with Selectors {
  _Sites(this.state);

  @override
  final AppState state;

  /// The values Sites watches while shown.
  List<String> get sitesKeys => [
    '${site.root}/sys/version',
    '${site.root}/sys/upstream_connected',
    '${site.root}/sys/downstream_connected',
  ];

  /// The node picked; this broker when none is.
  SitePick get sitePicked =>
      peers.selectedPeer ?? SitePick(SiteNode.self, site.viewed ?? '');

  List<Peer> get _peers => [for (final k in peers.view) ?peers.table[k]];

  List<QuarantineEntry> get _waiting => [
    for (final n in quarantine.view) ?quarantine.table[n],
  ];

  int _relays(String site, List<Peer> all) =>
      all.where((p) => p.kind == PeerKind.relayed && p.parent == site).length;

  /// The connections waiting to be let in, by their certificate's name.
  List<String> get sitesWaiting => [for (final q in _waiting) q.cn];

  /// What the user lacks to change `sys` (connect, issue a token, let one
  /// in, deauthorize).
  Lack? get sitesLack => site.lacks(Perm.config, '${site.root}/sys');

  /// The nodes of the map, in its rows' order.
  List<SiteMapNode> get siteMap {
    final viewed = site.viewed ?? '';
    final all = _peers;
    final waiting = _waiting;
    final self = SitePick(SiteNode.self, viewed);
    Iterable<Peer> of(PeerKind k) => all.where((p) => p.kind == k);
    final picked = sitePicked;
    return [
      for (final n in _nodes(viewed, all, waiting, self, of)) n._picked(picked),
    ];
  }

  List<SiteMapNode> _nodes(
    String viewed,
    List<Peer> all,
    List<QuarantineEntry> waiting,
    SitePick self,
    Iterable<Peer> Function(PeerKind) of,
  ) => [
    for (final p in of(PeerKind.upstream))
      SiteMapNode(
        pick: SitePick(SiteNode.upstream, p.site),
        name: p.site,
        connected: p.connected,
        status: p.status,
        offline: !p.connected,
      ),
    for (final p in of(PeerKind.platform))
      SiteMapNode(
        pick: SitePick(SiteNode.platform, p.site),
        name: p.site,
        detail: p.platform,
        parent: self,
      ),
    SiteMapNode(
      pick: self,
      name: viewed,
      parent: switch (of(PeerKind.upstream).firstOrNull) {
        final p? => SitePick(SiteNode.upstream, p.site),
        null => null,
      },
      offline: !site.connected,
    ),
    for (final p in of(PeerKind.downstream))
      SiteMapNode(
        pick: SitePick(SiteNode.downstream, p.site),
        name: p.site,
        count: _relays(p.site, all),
        parent: self,
      ),
    for (final q in waiting.where((q) => q.kind == QuarantineKind.broker))
      SiteMapNode(
        pick: SitePick(SiteNode.waiting, q.node),
        name: q.cn,
        count: q.via.length,
        parent: self,
        waitingBroker: true,
      ),
    for (final p in of(PeerKind.device))
      SiteMapNode(
        pick: SitePick(SiteNode.device, p.site),
        name: p.site,
        detail: p.url,
        offline: !p.connected,
        parent: self,
      ),
    for (final q in waiting.where((q) => q.kind != QuarantineKind.broker))
      SiteMapNode(
        pick: SitePick(SiteNode.waiting, q.node),
        name: q.cn,
        parent: self,
      ),
    for (final p in of(PeerKind.relayed))
      SiteMapNode(
        pick: SitePick(SiteNode.relayed, p.site),
        name: p.site,
        detail: p.parent,
        parent: SitePick(SiteNode.downstream, p.parent ?? ''),
      ),
  ];

  Peer? _peer(PeerKind kind, String name) =>
      _peers.where((p) => p.kind == kind && p.site == name).firstOrNull;

  /// What the inspector shows for the node picked; null for a quarantine
  /// entry that is gone.
  SiteDetail? get siteDetail {
    final root = site.root ?? '';
    final all = _peers;
    final SitePick(:node, :name) = sitePicked;
    return switch (node) {
      SiteNode.self => SelfDetail(
        name,
        '$root/sys',
        connected: site.connected,
        upstreams: [
          for (final p in all)
            if (p.kind == PeerKind.upstream) p.site,
        ],
        below: all.where((p) => p.kind == PeerKind.downstream).length,
        devices: all.where((p) => p.kind == PeerKind.device).length,
        version: switch (live.values['$root/sys/version']?.value) {
          null => null,
          final v => '$v',
        },
      ),
      SiteNode.upstream => UpstreamDetail(
        name,
        '$root/sys/upstream/$name',
        connected: _peer(PeerKind.upstream, name)?.connected ?? false,
        url: _peer(PeerKind.upstream, name)?.url,
        status: _peer(PeerKind.upstream, name)?.status,
        allowConfig: _peer(PeerKind.upstream, name)?.allowConfig,
      ),
      SiteNode.downstream => DownstreamDetail(
        name,
        '$root/downstream/$name',
        relays: _relays(name, all),
      ),
      SiteNode.waiting => switch (quarantine.table[name]) {
        null => null,
        final q => WaitingDetail(
          name,
          'sys/quarantine/$name',
          entry: q,
          form: q.kind == QuarantineKind.broker ? quarantine.forms[name] : null,
        ),
      },
      SiteNode.device => DeviceDetail(
        name,
        'sys/links/$name',
        // live: the link's state as the broker publishes it now
        connected: links.table[name]?.state == LinkState.connected,
        device: links.table[name]?.device,
        branch: '$root/downstream/$name',
      ),
      SiteNode.relayed => RelayedDetail(
        name,
        'wy/$name',
        through: _peer(PeerKind.relayed, name)?.parent ?? '',
      ),
      SiteNode.platform => PlatformDetail(
        name,
        '$root/downstream/uplink/$name',
        platform: _peer(PeerKind.platform, name)?.platform,
      ),
    };
  }
}

// What Sites shows, as functions of the state: the selectors of
// `SelectPeers` (business/lib/redux/selectors.dart) call them.
List<String> sitesKeysOf(AppState s) => _Sites(s).sitesKeys;

SitePick sitePickedOf(AppState s) => _Sites(s).sitePicked;

List<String> sitesWaitingOf(AppState s) => _Sites(s).sitesWaiting;

Lack? sitesLackOf(AppState s) => _Sites(s).sitesLack;

List<SiteMapNode> siteMapOf(AppState s) => _Sites(s).siteMap;

SiteDetail? siteDetailOf(AppState s) => _Sites(s).siteDetail;
