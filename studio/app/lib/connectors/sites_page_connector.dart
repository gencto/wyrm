import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/links/actions/deauthorize_link_action.dart';
import 'package:business/redux/links/actions/retrieve_links_action.dart';
import 'package:business/redux/links/actions/set_tab_action.dart';
import 'package:business/redux/live/actions/unwatch_keys_action.dart';
import 'package:business/redux/live/actions/watch_keys_action.dart';
import 'package:business/redux/nodes/actions/invoke_node_action.dart';
import 'package:business/redux/nodes/actions/retrieve_node_detail_action.dart';
import 'package:business/redux/nodes/actions/select_node_action.dart';
import 'package:business/redux/peers/actions/add_upstream_action.dart';
import 'package:business/redux/peers/actions/authorize_broker_action.dart';
import 'package:business/redux/peers/actions/issue_site_token_action.dart';
import 'package:business/redux/peers/actions/retrieve_peers_action.dart';
import 'package:business/redux/peers/actions/set_selected_peer_action.dart';
import 'package:business/redux/quarantine/actions/reject_quarantine_action.dart';
import 'package:business/redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'package:business/redux/site/actions/view_site_action.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/links_tab.dart';
import 'package:models/peer.dart';
import 'package:models/peer_kind.dart';
import 'package:ui/buttons/action_row.dart';
import 'package:ui/charts/site_map.dart';
import 'package:ui/containers/detail_inspector.dart';
import 'package:ui/containers/fact_grid.dart';
import 'package:ui/forms/action_form.dart';
import 'package:ui/forms/param_form.dart';
import 'package:ui/indicators/status_pill.dart';
import 'package:ui/models/tone.dart';
import 'package:ui/overlays/confirm_dialog.dart';
import 'package:ui/overlays/log_view.dart';
import 'package:ui/overlays/panel_dialog.dart';
import 'package:ui/pages/sites_page.dart';

import '../common/forms.dart';
import '../common/tab_visibility.dart';

@RoutePage()
class SitesPageConnector extends StatelessWidget {
  const SitesPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => TabVisibility(
      onShow: vm.onShow,
      onHide: vm.onHide,
      child: SitesPage(
        title: S.current.sitesAround(vm.site),
        subtitle: S.current.sitesSubtitle(vm.site),
        connectLabel: S.current.connectUpstream,
        tokenLabel: S.current.tokenForBelow,
        connectReason: vm.configReason,
        legend: (
          S.current.legendConnected,
          S.current.legendOffline,
          S.current.legendWaiting,
          S.current.legendPlatform,
        ),
        nodes: vm.nodes,
        onNode: vm.onNode,
        onConnect: () => vm.onConnect(context),
        onToken: () => vm.onToken(context),
        waiting: vm.waiting,
        reviewLabel: S.current.review,
        onReview: () => vm.onReview(context),
        inspector: vm.inspector,
        onAction: (a) => vm.onAction(context, a),
        onSubmit: vm.onSubmit,
        onSecondary: () => vm.onAction(context, 'reject'),
        busy: vm.busy,
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, SitesPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  String get _root => site.root ?? '';

  List<String> get _watch => [
    '$_root/sys/version',
    '$_root/sys/upstream_connected',
    '$_root/sys/downstream_connected',
  ];

  @override
  _Vm fromStore() {
    final viewed = site.viewed ?? '';
    final peerList = [for (final k in peers.view) ?peers.table[k]];
    final waiting = [for (final n in quarantine.view) ?quarantine.table[n]];
    final sel = peers.selectedPeer ?? 'self:$viewed';
    final nodes = <SiteNodeVm>[
      for (final p in peerList.where((p) => p.kind == PeerKind.upstream))
        SiteNodeVm(
          id: 'upstream:${p.site}',
          name: p.site,
          kind: SiteNodeKind.upstream,
          sub: p.connected
              ? S.current.yourUpstream
              : (p.status ?? S.current.stateOffline),
          offline: !p.connected,
          selected: sel == 'upstream:${p.site}',
        ),
      for (final p in peerList.where((p) => p.kind == PeerKind.platform))
        SiteNodeVm(
          id: 'platform:${p.site}',
          name: p.site,
          kind: SiteNodeKind.platform,
          sub: p.platform ?? '',
          tag: 'UP',
          parent: 'self:$viewed',
          selected: sel == 'platform:${p.site}',
        ),
      SiteNodeVm(
        id: 'self:$viewed',
        name: viewed,
        kind: SiteNodeKind.self,
        sub: S.current.thisBroker,
        tag: S.current.youTag,
        parent: peerList
            .where((p) => p.kind == PeerKind.upstream)
            .map((p) => 'upstream:${p.site}')
            .firstOrNull,
        offline: !site.connected,
        selected: sel == 'self:$viewed',
      ),
      for (final p in peerList.where((p) => p.kind == PeerKind.downstream))
        SiteNodeVm(
          id: 'downstream:${p.site}',
          name: p.site,
          kind: SiteNodeKind.downstream,
          sub: _relays(p.site, peerList),
          parent: 'self:$viewed',
          selected: sel == 'downstream:${p.site}',
        ),
      for (final q in waiting.where((q) => q.kind == 'broker'))
        SiteNodeVm(
          id: 'waiting:${q.node}',
          name: q.cn,
          kind: SiteNodeKind.waitingBroker,
          sub: q.via.isEmpty
              ? S.current.asksToJoin
              : S.current.asksToJoinRelays(q.via.length),
          parent: 'self:$viewed',
          selected: sel == 'waiting:${q.node}',
        ),
      for (final p in peerList.where((p) => p.kind == PeerKind.device))
        SiteNodeVm(
          id: 'device:${p.site}',
          name: p.site,
          kind: SiteNodeKind.device,
          sub: p.url ?? '',
          offline: !p.connected,
          parent: 'self:$viewed',
          selected: sel == 'device:${p.site}',
        ),
      for (final q in waiting.where((q) => q.kind != 'broker'))
        SiteNodeVm(
          id: 'waiting:${q.node}',
          name: q.cn,
          kind: SiteNodeKind.waitingLink,
          sub: S.current.newCertificate,
          parent: 'self:$viewed',
          selected: sel == 'waiting:${q.node}',
        ),
      for (final p in peerList.where((p) => p.kind == PeerKind.relayed))
        SiteNodeVm(
          id: 'relayed:${p.site}',
          name: p.site,
          kind: SiteNodeKind.relayed,
          sub: S.current.viaSite(p.parent ?? ''),
          parent: 'downstream:${p.parent}',
          selected: sel == 'relayed:${p.site}',
        ),
    ];
    final busy = peers.isWaiting || quarantine.isWaiting;
    return _Vm(
      site: viewed,
      configReason: site.needs('config', '$_root/sys'),
      nodes: nodes,
      waiting: waiting.isEmpty
          ? null
          : S.current.waitingToBeLetIn(
              waiting.length,
              waiting.map((q) => q.cn).join(', '),
            ),
      inspector: _inspector(sel, peerList),
      busy: busy,
      onShow: () {
        dispatchSync(WatchKeysAction(_watch));
        unawaited(_load());
      },
      onHide: () => dispatchSync(UnwatchKeysAction(_watch)),
      onNode: (id) => dispatchSync(SetSelectedPeerAction(id)),
      onReview: (context) {
        dispatchSync(SetTabAction(LinksTab.quarantine));
        AutoTabsRouter.of(context).setActiveIndex(1);
      },
      onConnect: _connect,
      onToken: _token,
      onAction: _action,
      onSubmit: (values) {
        final id = peers.selectedPeer ?? '';
        return id.startsWith('waiting:')
            ? sendForm(
                dispatchAndWait(
                  AuthorizeBrokerAction(id.substring(8), plainArgs(values)),
                ),
              )
            : null;
      },
    );
  }

  Future<void> _load() async {
    await dispatchAndWait(RetrieveLinksAction());
    await dispatchAndWait(RetrieveQuarantineAction());
    await dispatchAndWait(RetrievePeersAction());
  }

  static String _relays(String site, List<Peer> all) {
    final n = all
        .where((p) => p.kind == PeerKind.relayed && p.parent == site)
        .length;
    return n == 0 ? S.current.downstream : S.current.relaysSites(n);
  }

  DetailInspectorVm? _inspector(String sel, List<Peer> all) {
    final (kind, name) = (
      sel.substring(0, sel.indexOf(':')),
      sel.substring(sel.indexOf(':') + 1),
    );
    final reason = site.needs('config', '$_root/sys');
    ActionRowVm row(
      String id,
      String icon,
      String t,
      String d,
      String code, {
      Tone tone = Tone.neutral,
      String? off,
    }) => ActionRowVm(
      id: id,
      icon: icon,
      title: t,
      description: d,
      code: code,
      tone: tone,
      disabledReason: off,
    );
    switch (kind) {
      case 'self':
        final below = all.where((p) => p.kind == PeerKind.downstream).length;
        final devices = all.where((p) => p.kind == PeerKind.device).length;
        final ups = all
            .where((p) => p.kind == PeerKind.upstream)
            .map((p) => p.site)
            .toList();
        return DetailInspectorVm(
          eyebrow: S.current.thisBroker,
          title: name,
          pill: site.connected
              ? StatusPillVm(label: S.current.stateConnected, tone: Tone.good)
              : StatusPillVm(label: S.current.stateOffline, tone: Tone.neutral),
          keyName: '$_root/sys',
          facts: [
            FactVm(
              label: S.current.factUpstreams,
              value: ups.isEmpty ? S.current.noUpstream(name) : ups.join(', '),
            ),
            FactVm(
              label: S.current.factBelow,
              value: S.current.brokersDevices(below, devices),
            ),
            if (live.values['$_root/sys/version']?.value case final v?)
              FactVm(label: S.current.factVersion, value: 'wyrmd $v'),
          ],
          groups: [
            ActionGroupVm(
              label: S.current.letOthersIn,
              actions: [
                row(
                  'token',
                  'action_key',
                  S.current.tokenForBelow,
                  S.current.tokenNote,
                  'sys/tokens add',
                  tone: Tone.ember,
                  off: reason,
                ),
                row(
                  'admission',
                  'action_lock',
                  S.current.quarantineAndAdmission,
                  S.current.quarantineAndAdmissionNote,
                  'enable_quarantine',
                ),
              ],
            ),
            ActionGroupVm(
              label: S.current.goUp,
              actions: [
                row(
                  'connect',
                  'action_up',
                  S.current.connectUpstream,
                  S.current.connectNote(name),
                  'sys/upstream add',
                  off: reason,
                ),
              ],
            ),
          ],
        );
      case 'upstream':
        final p = peers.table[sel];
        return DetailInspectorVm(
          eyebrow: S.current.upstreamBroker,
          title: name,
          pill: (p?.connected ?? false)
              ? StatusPillVm(label: S.current.stateConnected, tone: Tone.good)
              : StatusPillVm(label: S.current.stateOffline, tone: Tone.neutral),
          keyName: '$_root/sys/upstream/$name',
          facts: [
            if (p?.url case final u?)
              FactVm(label: 'URL', value: u, mono: true),
            if (p?.status case final s?)
              FactVm(label: S.current.factStatus, value: s),
            if (p?.allowConfig case final a?)
              FactVm(
                label: S.current.factAllowConfig,
                value: a ? S.current.yes : S.current.no,
              ),
          ],
          footer: S.current.upstreamFooter,
        );
      case 'downstream':
        return DetailInspectorVm(
          eyebrow: S.current.downstreamBroker,
          title: name,
          pill: StatusPillVm(label: S.current.stateConnected, tone: Tone.good),
          keyName: '$_root/downstream/$name',
          facts: [
            FactVm(label: S.current.factRelays, value: _relays(name, all)),
            FactVm(label: S.current.factTree, value: 'wy/$name', mono: true),
          ],
          groups: [
            ActionGroupVm(
              label: S.current.groupWork,
              actions: [
                row(
                  'open',
                  'ws_explorer',
                  S.current.openItsTree,
                  S.current.openItsTreeNote(name),
                  'wy/$name',
                ),
                row(
                  'deauthorize',
                  'action_block',
                  S.current.actDeauthorize,
                  S.current.deauthorizeBrokerNote,
                  'deauthorize',
                  tone: Tone.warn,
                  off: reason,
                ),
              ],
            ),
          ],
        );
      case 'waiting':
        final q = quarantine.table[name];
        if (q == null) {
          return null;
        }
        final specs = quarantine.forms[name];
        final broker = q.kind == 'broker';
        return DetailInspectorVm(
          eyebrow: broker
              ? S.current.brokerWaiting
              : S.current.waitingInQuarantine,
          title: q.cn,
          pill: StatusPillVm(
            label: S.current.stateWaiting,
            tone: Tone.warn,
            mark: .ring,
          ),
          keyName: 'sys/quarantine/$name',
          facts: [
            if (q.from case final f?)
              FactVm(label: S.current.factFrom, value: f, mono: true),
            if (q.via.isNotEmpty)
              FactVm(
                label: S.current.factRelays,
                value: q.via.join(', '),
                mono: true,
              ),
            if (q.key case final k?)
              FactVm(label: S.current.factKey, value: k, mono: true),
          ],
          form: !broker || specs == null
              ? null
              : InspectorFormVm(
                  id: name,
                  label: S.current.letTheBrokerIn,
                  fields: paramFields(specs),
                  submit: S.current.approve,
                  secondary: S.current.reject,
                  note: S.current.approveBrokerNote,
                  disabledReason: reason,
                ),
          groups: broker
              ? const []
              : [
                  ActionGroupVm(
                    label: S.current.groupWork,
                    actions: [
                      row(
                        'links-quarantine',
                        'ws_links',
                        S.current.decideInLinks,
                        S.current.decideInLinksNote,
                        'sys/quarantine',
                      ),
                    ],
                  ),
                ],
        );
      case 'device':
        final l = links.table[name];
        return DetailInspectorVm(
          eyebrow: S.current.runsOnAnotherDevice,
          title: name,
          pill: l?.state == 'connected'
              ? StatusPillVm(label: S.current.stateConnected, tone: Tone.good)
              : StatusPillVm(label: S.current.stateOffline, tone: Tone.neutral),
          keyName: 'sys/links/$name',
          facts: [
            if (l?.device case final d?)
              FactVm(label: S.current.factDevice, value: d, mono: true),
            FactVm(
              label: S.current.factBranch,
              value: '$_root/downstream/$name',
              mono: true,
            ),
          ],
          groups: [
            ActionGroupVm(
              label: S.current.groupWork,
              actions: [
                row(
                  'links-remote',
                  'ws_links',
                  S.current.openInLinks,
                  S.current.openInLinksNote,
                  'sys/links',
                ),
              ],
            ),
          ],
        );
      case 'relayed':
        return DetailInspectorVm(
          eyebrow: S.current.siteRelayedBelow,
          title: name,
          keyName: 'wy/$name',
          facts: [
            FactVm(
              label: S.current.factThrough,
              value: peers.table[sel]?.parent ?? '',
            ),
          ],
          groups: [
            ActionGroupVm(
              label: S.current.groupWork,
              actions: [
                row(
                  'open',
                  'ws_explorer',
                  S.current.openItsTree,
                  S.current.openItsTreeNote(name),
                  'wy/$name',
                ),
              ],
            ),
          ],
          footer: S.current.relayedFooter,
        );
      case 'platform':
        final p = peers.table[sel];
        return DetailInspectorVm(
          eyebrow: S.current.platform,
          title: name,
          keyName: '$_root/downstream/uplink/$name',
          facts: [
            if (p?.platform case final k?)
              FactVm(label: S.current.factKind, value: k),
          ],
          groups: [
            ActionGroupVm(
              label: S.current.groupWork,
              actions: [
                row(
                  'platform',
                  'ws_explorer',
                  S.current.openInExplorer,
                  S.current.platformNote,
                  'downstream/uplink',
                ),
              ],
            ),
          ],
        );
    }
    return null;
  }

  Future<void> _action(BuildContext context, String a) async {
    final sel = peers.selectedPeer ?? 'self:${site.viewed}';
    final name = sel.substring(sel.indexOf(':') + 1);
    switch (a) {
      case 'token':
        await _token(context);
      case 'connect':
        await _connect(context);
      case 'admission' || 'links-quarantine':
        dispatchSync(SetTabAction(LinksTab.quarantine));
        AutoTabsRouter.of(context).setActiveIndex(1);
      case 'links-remote':
        dispatchSync(SetTabAction(LinksTab.remote));
        AutoTabsRouter.of(context).setActiveIndex(1);
      case 'open':
        dispatchSync(ViewSiteAction(name));
        AutoTabsRouter.of(context).setActiveIndex(0);
      case 'platform':
        dispatchSync(SelectNodeAction('$_root/downstream/uplink/$name'));
        AutoTabsRouter.of(context).setActiveIndex(0);
      case 'deauthorize':
        if (await ConfirmDialog.ask(
          context,
          title: S.current.deauthorizeTitle(name),
          message: S.current.deauthorizeBrokerNote,
          confirm: S.current.actDeauthorize,
          cancel: S.current.cancel,
        )) {
          await dispatchAndWait(DeauthorizeLinkAction(name));
          await dispatchAndWait(RetrievePeersAction());
        }
      case 'reject':
        if (context.mounted &&
            await ConfirmDialog.ask(
              context,
              title: S.current.rejectTitle(quarantine.table[name]?.cn ?? name),
              message: S.current.rejectNote,
              confirm: S.current.reject,
              cancel: S.current.cancel,
            )) {
          await dispatchAndWait(RejectQuarantineAction(name));
        }
    }
  }

  Future<void> _connect(BuildContext context) async {
    final key = '$_root/sys/upstream';
    await dispatchAndWait(RetrieveNodeDetailAction(key));
    final add = state.nodes.detail[key]?.actions
        .where((x) => x.name == 'add')
        .firstOrNull;
    if (add == null || !context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialog) => PanelDialog(
        title: S.current.connectUpstream,
        width: 640,
        note: S.current.connectNote(site.viewed ?? ''),
        child: ActionForm(
          fields: paramFields(add.params),
          submit: S.current.connect,
          onSubmit: (v) => sendForm(
            dispatchAndWait(AddUpstreamAction(plainArgs(v))),
            onOk: () {
              if (dialog.mounted) {
                Navigator.of(dialog).pop();
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _token(BuildContext context) async {
    final key = '$_root/sys/tokens';
    var issued = false;
    await showDialog<void>(
      context: context,
      builder: (dialog) => PanelDialog(
        title: S.current.tokenForBelow,
        width: 640,
        note: S.current.tokenNote,
        child: StatefulBuilder(
          builder: (context, setState) {
            final lines =
                state.nodes.results[InvokeNodeAction.resultId(key, 'add')];
            if (issued && lines != null) {
              return SizedBox(height: 180, child: LogView(lines: lines.unlock));
            }
            return ActionForm(
              fields: [
                ParamFieldVm(
                  id: 'count',
                  label: S.current.tokenUses,
                  kind: ParamKind.number,
                  value: 1,
                  onChanged: (_) {},
                ),
                ParamFieldVm(
                  id: 'hours',
                  label: S.current.tokenHours,
                  kind: ParamKind.number,
                  value: 24,
                  onChanged: (_) {},
                ),
              ],
              submit: S.current.issue,
              onSubmit: (v) => sendForm(
                dispatchAndWait(
                  IssueSiteTokenAction(
                    count: (v['count'] as num?)?.toInt() ?? 1,
                    hours: (v['hours'] as num?)?.toInt() ?? 24,
                  ),
                ),
                onOk: () => setState(() => issued = true),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.site,
    required this.configReason,
    required this.nodes,
    required this.waiting,
    required this.inspector,
    required this.busy,
    required this.onShow,
    required this.onHide,
    required this.onNode,
    required this.onReview,
    required this.onConnect,
    required this.onToken,
    required this.onAction,
    required this.onSubmit,
  }) : super(equals: [site, configReason, nodes, waiting, inspector, busy]);

  final String site;
  final String? configReason;
  final List<SiteNodeVm> nodes;
  final String? waiting;
  final DetailInspectorVm? inspector;
  final bool busy;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final ValueChanged<String> onNode;
  final ValueChanged<BuildContext> onReview;
  final Future<void> Function(BuildContext context) onConnect;
  final Future<void> Function(BuildContext context) onToken;
  final Future<void> Function(BuildContext context, String action) onAction;
  final FutureOr<FieldRefusal?> Function(Map<String, Object?> values) onSubmit;
}
