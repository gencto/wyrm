import 'package:business/wyrm/sites.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/site_node.dart';
import 'package:models/site_pick.dart';
import 'package:ui/charts/site_map.dart';
import 'package:ui/pages/sites_page.dart';

import '../common/forms.dart';

/// A node of the domain as the map draws it; a waiting one by what waits
/// (`broker`: a broker, else a link).
extension SitePickRef on SitePick {
  SiteRef ref({bool broker = false}) => SiteRef(switch (node) {
    SiteNode.self => .self,
    SiteNode.upstream => .upstream,
    SiteNode.platform => .platform,
    SiteNode.downstream => .downstream,
    SiteNode.waiting => broker ? .waitingBroker : .waitingLink,
    SiteNode.device => .device,
    SiteNode.relayed => .relayed,
  }, name);
}

/// A node of the map as the domain picks it.
extension SiteRefPick on SiteRef {
  SitePick get pick => SitePick(switch (kind) {
    SiteNodeKind.self => .self,
    SiteNodeKind.upstream => .upstream,
    SiteNodeKind.platform => .platform,
    SiteNodeKind.downstream => .downstream,
    SiteNodeKind.waitingBroker || SiteNodeKind.waitingLink => .waiting,
    SiteNodeKind.device => .device,
    SiteNodeKind.relayed => .relayed,
  }, name);
}

extension SiteMapNodeData on SiteMapNode {
  SiteNodeData get data => SiteNodeData(
    ref: pick.ref(broker: waitingBroker),
    name: name,
    parent: parent?.ref(),
    offline: offline,
    connected: connected,
    status: status,
    detail: detail,
    count: count,
    notRead: notRead,
    selected: selected,
  );
}

/// What the inspector shows, as `SitesPage` words it.
extension SiteDetailVmOf on SiteDetail {
  SiteDetailVm get vm => switch (this) {
    SelfDetail(:final name, :final key) && final d => SelfSiteVm(
      name,
      key,
      connected: d.connected,
      upstreams: d.upstreams,
      below: d.below,
      devices: d.devices,
      version: d.version,
    ),
    UpstreamDetail(:final name, :final key) && final d => UpstreamSiteVm(
      name,
      key,
      connected: d.connected,
      url: d.url,
      status: d.status,
      allowConfig: d.allowConfig,
    ),
    DownstreamDetail(:final name, :final key) && final d => DownstreamSiteVm(
      name,
      key,
      relays: d.relays,
    ),
    WaitingDetail(:final name, :final key, :final entry, :final form) =>
      switch (entry) {
        QuarantineLink(:final cn, :final from) => WaitingLinkSiteVm(
          name,
          key,
          cn: cn,
          from: from,
        ),
        QuarantineBroker(
          :final cn,
          :final from,
          :final via,
          key: final hash,
        ) =>
          WaitingBrokerSiteVm(
            name,
            key,
            cn: cn,
            from: from,
            via: via.unlock,
            hash: hash,
            fields: form == null ? null : paramFields(form),
          ),
        QuarantineNotRead(:final cn) => WaitingNotReadSiteVm(
          name,
          key,
          cn: cn,
        ),
      },
    DeviceDetail(:final name, :final key) && final d => DeviceSiteVm(
      name,
      key,
      branch: d.branch,
      connected: d.connected,
      device: d.device,
    ),
    RelayedDetail(:final name, :final key, :final through) => RelayedSiteVm(
      name,
      key,
      through: through,
    ),
    PlatformDetail(:final name, :final key, :final platform) => PlatformSiteVm(
      name,
      key,
      platform: platform,
    ),
  };
}
