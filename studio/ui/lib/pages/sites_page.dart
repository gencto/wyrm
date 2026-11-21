import 'package:equatable/equatable.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';

import '../buttons/action_row.dart';
import '../buttons/button.dart';
import '../charts/site_map.dart';
import '../containers/detail_inspector.dart';
import '../containers/fact_grid.dart';
import '../containers/page_header.dart';
import '../forms/action_form.dart';
import '../forms/param_form.dart';
import '../indicators/app_icon.dart';
import '../indicators/status_pill.dart';
import '../models/disabled.dart';
import '../models/tone.dart';
import '../theme/extensions/colors.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// A node of the Sites map: what it is and its name.
final class SiteRef extends Equatable {
  const SiteRef(this.kind, this.name);

  final SiteNodeKind kind;
  final String name;

  @override
  List<Object?> get props => [kind, name];
}

/// An action of Sites' inspector.
enum SiteAct {
  /// `sys/tokens add`: a token for a site below.
  token,

  /// Quarantine and admission: Links › Quarantine.
  admission,

  /// `sys/upstream add`.
  connect,

  /// The site's own tree, in Explorer.
  open,

  /// A broker below loses its rights.
  deauthorize,

  /// A link waiting: decide in Links › Quarantine.
  decideInLinks,

  /// A link on another device: Links › On other devices.
  openInLinks,

  /// A platform: its node in Explorer.
  platform,
}

/// Where a link of Sites leads.
enum SiteGo {
  /// Links › Quarantine.
  quarantine,

  /// Links › On other devices.
  remote,

  /// The picked site's own tree, in Explorer.
  tree,

  /// The picked platform's node, in Explorer.
  platform,
}

/// One node of the map and what its line says: a peer's [status] or
/// [detail] (a platform's kind, a device's address, the site a relayed one
/// comes through) and a [count] (the sites a broker below relays, the
/// relays of a waiting broker).
final class SiteNodeData extends Equatable {
  const SiteNodeData({
    required this.ref,
    required this.name,
    this.parent,
    this.offline = false,
    this.connected = false,
    this.status,
    this.detail,
    this.count = 0,
    this.notRead = false,
    this.selected = false,
  });

  final SiteRef ref;
  final String name;
  final SiteRef? parent;
  final bool offline;
  final bool connected;
  final String? status;
  final String? detail;
  final int count;

  /// The node was answered in a form Studio does not read.
  final bool notRead;

  /// The node picked.
  final bool selected;

  @override
  List<Object?> get props => [
    ref,
    name,
    parent,
    offline,
    connected,
    status,
    detail,
    count,
    notRead,
    selected,
  ];
}

/// What the inspector shows for the node picked: its [name] and the key
/// written under its title.
sealed class SiteDetailVm extends Equatable {
  const SiteDetailVm(this.name, this.key);

  final String name;
  final String key;
}

/// This broker.
final class SelfSiteVm extends SiteDetailVm {
  const SelfSiteVm(
    super.name,
    super.key, {
    this.connected = false,
    this.upstreams = const [],
    this.below = 0,
    this.devices = 0,
    this.version,
  });

  final bool connected;
  final List<String> upstreams;
  final int below;
  final int devices;
  final String? version;

  @override
  List<Object?> get props => [
    name,
    key,
    connected,
    upstreams,
    below,
    devices,
    version,
  ];
}

/// An upstream broker.
final class UpstreamSiteVm extends SiteDetailVm {
  const UpstreamSiteVm(
    super.name,
    super.key, {
    this.connected = false,
    this.url,
    this.status,
    this.allowConfig,
  });

  final bool connected;
  final String? url;
  final String? status;
  final bool? allowConfig;

  @override
  List<Object?> get props => [name, key, connected, url, status, allowConfig];
}

/// A broker below.
final class DownstreamSiteVm extends SiteDetailVm {
  const DownstreamSiteVm(super.name, super.key, {this.relays = 0});

  final int relays;

  @override
  List<Object?> get props => [name, key, relays];
}

/// A connection waiting in quarantine: a link, a downstream broker (with
/// the [WaitingBrokerSiteVm.fields] of its `approve`), or an entry Studio
/// could not read.
sealed class WaitingSiteVm extends SiteDetailVm {
  const WaitingSiteVm(super.name, super.key, {required this.cn});

  final String cn;
}

/// A link's certificate, decided in Links.
final class WaitingLinkSiteVm extends WaitingSiteVm {
  const WaitingLinkSiteVm(
    super.name,
    super.key, {
    required super.cn,
    this.from,
  });

  final String? from;

  @override
  List<Object?> get props => [name, key, cn, from];
}

/// A downstream broker asking for Authorize.
final class WaitingBrokerSiteVm extends WaitingSiteVm {
  const WaitingBrokerSiteVm(
    super.name,
    super.key, {
    required super.cn,
    this.from,
    this.via = const [],
    this.hash,
    this.fields,
  });

  final String? from;
  final List<String> via;

  /// The key hash to compare.
  final String? hash;
  final List<ParamFieldVm>? fields;

  @override
  List<Object?> get props => [name, key, cn, from, via, hash, fields];
}

/// An entry Studio could not read: what waits is not known.
final class WaitingNotReadSiteVm extends WaitingSiteVm {
  const WaitingNotReadSiteVm(super.name, super.key, {required super.cn});

  @override
  List<Object?> get props => [name, key, cn];
}

/// A device of an external link.
final class DeviceSiteVm extends SiteDetailVm {
  const DeviceSiteVm(
    super.name,
    super.key, {
    required this.branch,
    this.connected = false,
    this.device,
  });

  final String branch;
  final bool connected;
  final String? device;

  @override
  List<Object?> get props => [name, key, branch, connected, device];
}

/// A site relayed below.
final class RelayedSiteVm extends SiteDetailVm {
  const RelayedSiteVm(super.name, super.key, {required this.through});

  final String through;

  @override
  List<Object?> get props => [name, key, through];
}

/// A platform the site sends to.
final class PlatformSiteVm extends SiteDetailVm {
  const PlatformSiteVm(super.name, super.key, {this.platform});

  final String? platform;

  @override
  List<Object?> get props => [name, key, platform];
}

/// What Sites draws.
final class SitesVm extends Equatable {
  const SitesVm({
    required this.site,
    this.nodes = const [],
    this.waiting = const [],
    this.detail,
    this.lack,
    this.busy = false,
  });

  final String site;
  final List<SiteNodeData> nodes;

  /// The certificates waiting to be let in.
  final List<String> waiting;
  final SiteDetailVm? detail;

  /// What the user lacks to change `sys`.
  final Disabled? lack;
  final bool busy;

  @override
  List<Object?> get props => [
    site,
    nodes,
    waiting,
    detail,
    lack,
    busy,
  ];
}

/// Board *Studio · Sites* (and its shapes Chain, Star, Two upstreams): a
/// header with Connect to an upstream and Token for a site below, the
/// waiting banner, the map with its legend, and the inspector of the
/// selected node.
class SitesPage extends StatelessWidget {
  const SitesPage({
    required this.vm,
    required this.onNode,
    required this.onConnect,
    required this.onToken,
    required this.onGo,
    required this.onDeauthorize,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final SitesVm vm;
  final ValueChanged<SiteRef> onNode;
  final VoidCallback onConnect;
  final VoidCallback onToken;

  /// A link to another workspace (Review, an inspector's row).
  final ValueChanged<SiteGo> onGo;

  /// The broker below picked loses its rights (asked first by the caller).
  final VoidCallback onDeauthorize;

  /// The waiting broker's form, approved.
  final FormSubmit onApprove;
  final VoidCallback onReject;

  /// What a row of the inspector does.
  void _act(SiteAct a) => switch (a) {
    SiteAct.token => onToken(),
    SiteAct.connect => onConnect(),
    SiteAct.deauthorize => onDeauthorize(),
    SiteAct.admission || SiteAct.decideInLinks => onGo(SiteGo.quarantine),
    SiteAct.openInLinks => onGo(SiteGo.remote),
    SiteAct.open => onGo(SiteGo.tree),
    SiteAct.platform => onGo(SiteGo.platform),
  };

  String _sub(SiteNodeData n) {
    final s = S.current;
    if (n.notRead) {
      return s.waitNotRead;
    }
    return switch (n.ref.kind) {
      SiteNodeKind.upstream =>
        n.connected ? s.yourUpstream : (n.status ?? s.stateOffline),
      SiteNodeKind.platform => n.detail ?? '',
      SiteNodeKind.self => s.thisBroker,
      SiteNodeKind.downstream =>
        n.count == 0 ? s.downstream : s.relaysSites(n.count),
      SiteNodeKind.waitingBroker =>
        n.count == 0 ? s.asksToJoin : s.asksToJoinRelays(n.count),
      SiteNodeKind.device => n.detail ?? '',
      SiteNodeKind.waitingLink => s.newCertificate,
      SiteNodeKind.relayed => s.viaSite(n.detail ?? ''),
    };
  }

  String? _tag(SiteNodeKind kind) => switch (kind) {
    SiteNodeKind.platform => 'UP',
    SiteNodeKind.self => S.current.youTag,
    SiteNodeKind.upstream ||
    SiteNodeKind.downstream ||
    SiteNodeKind.waitingBroker ||
    SiteNodeKind.device ||
    SiteNodeKind.waitingLink ||
    SiteNodeKind.relayed => null,
  };

  List<SiteNodeVm<SiteRef>> get _nodes => [
    for (final n in vm.nodes)
      SiteNodeVm(
        id: n.ref,
        name: n.name,
        kind: n.ref.kind,
        sub: _sub(n),
        // a small node draws no line under its name: the tag says it
        tag: n.notRead ? S.current.whyNotRead : _tag(n.ref.kind),
        parent: n.parent,
        offline: n.offline,
        selected: n.selected,
      ),
  ];

  static StatusPillVm _connected(bool on) => on
      ? StatusPillVm(label: S.current.stateConnected, tone: Tone.good)
      : StatusPillVm(label: S.current.stateOffline, tone: Tone.neutral);

  ActionRowVm<SiteAct> _row(
    SiteAct id,
    AppIcon icon,
    String title,
    String note,
    String code, {
    Tone tone = Tone.neutral,
    bool locked = false,
  }) => ActionRowVm(
    id: id,
    icon: icon,
    title: title,
    description: note,
    code: code,
    tone: tone,
    disabledReason: locked ? vm.lack?.text : null,
  );

  DetailInspectorVm<SiteAct>? get _inspector {
    final s = S.current;
    return switch (vm.detail) {
      null => null,
      SelfSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.thisBroker,
        title: name,
        pill: _connected(d.connected),
        keyName: key,
        facts: [
          FactVm(
            label: s.factUpstreams,
            value: d.upstreams.isEmpty
                ? s.noUpstream(name)
                : d.upstreams.join(', '),
          ),
          FactVm(
            label: s.factBelow,
            value: s.brokersDevices(d.below, d.devices),
          ),
          if (d.version case final v?)
            FactVm(label: s.factVersion, value: 'wyrmd $v'),
        ],
        groups: [
          ActionGroupVm(
            label: s.letOthersIn,
            actions: [
              _row(
                SiteAct.token,
                AppIcon.actionKey,
                s.tokenForBelow,
                s.tokenNote,
                'sys/tokens add',
                tone: Tone.ember,
                locked: true,
              ),
              _row(
                SiteAct.admission,
                AppIcon.actionLock,
                s.quarantineAndAdmission,
                s.quarantineAndAdmissionNote,
                'enable_quarantine',
              ),
            ],
          ),
          ActionGroupVm(
            label: s.goUp,
            actions: [
              _row(
                SiteAct.connect,
                AppIcon.actionUp,
                s.connectUpstream,
                s.connectNote(name),
                'sys/upstream add',
                locked: true,
              ),
            ],
          ),
        ],
      ),
      UpstreamSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.upstreamBroker,
        title: name,
        pill: _connected(d.connected),
        keyName: key,
        facts: [
          if (d.url case final u?) FactVm(label: 'URL', value: u, mono: true),
          if (d.status case final st?) FactVm(label: s.factStatus, value: st),
          if (d.allowConfig case final a?)
            FactVm(label: s.factAllowConfig, value: a ? s.yes : s.no),
        ],
        footer: s.upstreamFooter,
      ),
      DownstreamSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.downstreamBroker,
        title: name,
        pill: _connected(true),
        keyName: key,
        facts: [
          FactVm(
            label: s.factRelays,
            value: d.relays == 0 ? s.downstream : s.relaysSites(d.relays),
          ),
          FactVm(label: s.factTree, value: 'wy/$name', mono: true),
        ],
        groups: [
          ActionGroupVm(
            label: s.groupWork,
            actions: [
              _row(
                SiteAct.open,
                AppIcon.wsExplorer,
                s.openItsTree,
                s.openItsTreeNote(name),
                'wy/$name',
              ),
              _row(
                SiteAct.deauthorize,
                AppIcon.actionBlock,
                s.actDeauthorize,
                s.deauthorizeBrokerNote,
                'deauthorize',
                tone: Tone.warn,
                locked: true,
              ),
            ],
          ),
        ],
      ),
      WaitingSiteVm(:final key, :final cn) && final d => DetailInspectorVm(
        eyebrow: switch (d) {
          WaitingNotReadSiteVm() => s.waitNotRead,
          WaitingBrokerSiteVm() => s.brokerWaiting,
          WaitingLinkSiteVm() => s.waitingInQuarantine,
        },
        title: cn,
        pill: StatusPillVm(
          label: s.stateWaiting,
          tone: Tone.warn,
          mark: .ring,
        ),
        keyName: key,
        facts: [
          if (d
              case WaitingLinkSiteVm(from: final f?) ||
                  WaitingBrokerSiteVm(from: final f?))
            FactVm(label: s.factFrom, value: f, mono: true),
          if (d case WaitingBrokerSiteVm(:final via) when via.isNotEmpty)
            FactVm(label: s.factRelays, value: via.join(', '), mono: true),
          if (d case WaitingBrokerSiteVm(hash: final k?))
            FactVm(label: s.factKey, value: k, mono: true),
        ],
        form: switch (d) {
          WaitingBrokerSiteVm(:final fields?) => InspectorFormVm(
            id: d.name,
            label: s.letTheBrokerIn,
            fields: fields,
            submit: s.approve,
            secondary: s.reject,
            note: s.approveBrokerNote,
            disabledReason: vm.lack?.text,
          ),
          WaitingBrokerSiteVm() ||
          WaitingLinkSiteVm() ||
          WaitingNotReadSiteVm() => null,
        },
        groups: switch (d) {
          WaitingBrokerSiteVm() => const [],
          WaitingLinkSiteVm() || WaitingNotReadSiteVm() => [
            ActionGroupVm(
              label: s.groupWork,
              actions: [
                _row(
                  SiteAct.decideInLinks,
                  AppIcon.wsLinks,
                  s.decideInLinks,
                  s.decideInLinksNote,
                  'sys/quarantine',
                ),
              ],
            ),
          ],
        },
      ),
      DeviceSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.runsOnAnotherDevice,
        title: name,
        pill: _connected(d.connected),
        keyName: key,
        facts: [
          if (d.device case final dv?)
            FactVm(label: s.factDevice, value: dv, mono: true),
          FactVm(label: s.factBranch, value: d.branch, mono: true),
        ],
        groups: [
          ActionGroupVm(
            label: s.groupWork,
            actions: [
              _row(
                SiteAct.openInLinks,
                AppIcon.wsLinks,
                s.openInLinks,
                s.openInLinksNote,
                'sys/links',
              ),
            ],
          ),
        ],
      ),
      RelayedSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.siteRelayedBelow,
        title: name,
        keyName: key,
        facts: [FactVm(label: s.factThrough, value: d.through)],
        groups: [
          ActionGroupVm(
            label: s.groupWork,
            actions: [
              _row(
                SiteAct.open,
                AppIcon.wsExplorer,
                s.openItsTree,
                s.openItsTreeNote(name),
                'wy/$name',
              ),
            ],
          ),
        ],
        footer: s.relayedFooter,
      ),
      PlatformSiteVm(:final name, :final key) && final d => DetailInspectorVm(
        eyebrow: s.platform,
        title: name,
        keyName: key,
        facts: [
          if (d.platform case final k?) FactVm(label: s.factKind, value: k),
        ],
        groups: [
          ActionGroupVm(
            label: s.groupWork,
            actions: [
              _row(
                SiteAct.platform,
                AppIcon.wsExplorer,
                s.openInExplorer,
                s.platformNote,
                'downstream/uplink',
              ),
            ],
          ),
        ],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reason = vm.lack?.text;
    final body = ListView(
      padding: Insets.workspace,
      children: [
        PageHeader(
          title: S.current.sitesAround(vm.site),
          subtitle: S.current.sitesSubtitle(vm.site),
          trailing: Button.secondary(
            label: S.current.connectUpstream,
            icon: AppIcon.actionUp,
            disabledReason: reason,
            onPressed: reason == null ? onConnect : null,
          ),
        ),
        Gaps.underButtons,
        Align(
          alignment: .centerLeft,
          child: Button.secondary(
            label: S.current.tokenForBelow,
            icon: AppIcon.actionKey,
            disabledReason: reason,
            onPressed: reason == null ? onToken : null,
          ),
        ),
        if (vm.waiting.isNotEmpty) ...[
          Gaps.md,
          Container(
            padding: Insets.waiting,
            decoration: BoxDecoration(
              color: c.warnTint,
              border: .all(color: c.warnLine),
              borderRadius: Radii.control,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.current.waitingToBeLetIn(
                      vm.waiting.length,
                      vm.waiting.join(', '),
                    ),
                    style: TextStyle(fontSize: FontSizes.lg, color: c.text1),
                  ),
                ),
                TextButton(
                  onPressed: () => onGo(SiteGo.quarantine),
                  child: Text(
                    S.current.review,
                    style: TextStyle(color: c.emberSoft),
                  ),
                ),
              ],
            ),
          ),
        ],
        Gaps.aboveMap,
        Container(
          padding: Insets.map,
          decoration: BoxDecoration(
            color: c.ground0,
            border: .all(color: c.line1),
            borderRadius: Radii.panel,
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: AppSpacing.map,
            children: [
              const SiteLegend(),
              SiteMap(nodes: _nodes, onTap: onNode),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final ins = _inspector;
        if (ins == null || box.maxWidth < 1000) {
          return body;
        }
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(child: body),
            DetailInspector(
              vm: ins,
              onAction: _act,
              onSubmit: onApprove,
              onSecondary: onReject,
              busy: vm.busy,
            ),
          ],
        );
      },
    );
  }
}
