import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:models/agent_task.dart';
import 'package:models/audit_entry.dart';
import 'package:models/catalog_item.dart';
import 'package:models/flow_draft.dart';
import 'package:models/flow_summary.dart';
import 'package:models/grant.dart';
import 'package:models/hist_point.dart';
import 'package:models/install_source.dart';
import 'package:models/install_target.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/link_revision.dart';
import 'package:models/links_tab.dart';
import 'package:models/live_value.dart';
import 'package:models/login_failure.dart';
import 'package:models/node_detail.dart';
import 'package:models/node_info.dart';
import 'package:models/node_type.dart';
import 'package:models/package_check.dart';
import 'package:models/package_info.dart';
import 'package:models/panel_slot.dart';
import 'package:models/param_spec.dart';
import 'package:models/peer.dart';
import 'package:models/quarantine_entry.dart';
import 'package:models/role_grant.dart';
import 'package:models/site_choice.dart';
import 'package:models/staged_change.dart';
import 'package:models/task_event.dart';
import 'package:models/user_info.dart';
import 'package:models/watch_group.dart';
import 'package:models/workspace.dart';

import '../wyrm/keys.dart';
import 'access/actions/retrieve_access_action.dart';
import 'app_state.dart';
import 'assistant/actions/ask_agent_action.dart';
import 'assistant/actions/retrieve_agent_action.dart';
import 'changes/actions/apply_changes_action.dart';
import 'common/action.dart';
import 'flow_editor/actions/deploy_flow_action.dart';
import 'flows/actions/retrieve_flows_action.dart';
import 'historian/actions/retrieve_historian_action.dart';
import 'historian/actions/retrieve_series_action.dart';
import 'link_install/actions/install_link_action.dart';
import 'links/actions/deauthorize_link_action.dart';
import 'links/actions/get_link_log_action.dart';
import 'links/actions/grant_link_action.dart';
import 'links/actions/remove_link_action.dart';
import 'links/actions/retrieve_link_history_action.dart';
import 'links/actions/retrieve_links_action.dart';
import 'links/actions/rollback_link_params_action.dart';
import 'links/actions/start_link_action.dart';
import 'links/actions/stop_link_action.dart';
import 'login/actions/log_in_action.dart';
import 'login/actions/probe_gateway_action.dart';
import 'nodes/actions/retrieve_history_action.dart';
import 'nodes/actions/retrieve_node_detail_action.dart';
import 'nodes/actions/retrieve_nodes_action.dart';
import 'packages/actions/retrieve_packages_action.dart';
import 'peers/actions/retrieve_peers_action.dart';
import 'quarantine/actions/retrieve_quarantine_action.dart';
import 'session/actions/log_out_action.dart';
import 'site/actions/retrieve_sites_action.dart';
import 'system/actions/retrieve_system_log_action.dart';
import 'tasks/actions/retrieve_tasks_action.dart';

/// The facade: mix it in and every substate's selectors are in scope.
///
/// `Action` mixes it in, and so does every connector's `_Factory` — which is
/// the whole surface. A reducer reads `login.email`; nothing has to go through
/// a root type and a hop to get there.
mixin Selectors {
  AppState get state;

  SelectConnectivity get connectivity => SelectConnectivity(state);
  SelectLogin get login => SelectLogin(state);
  SelectSession get session => SelectSession(state);
  SelectTheme get theme => SelectTheme(state);
  SelectLanguage get language => SelectLanguage(state);
  SelectSite get site => SelectSite(state);
  SelectNodes get nodes => SelectNodes(state);
  SelectLive get live => SelectLive(state);
  SelectLinks get links => SelectLinks(state);
  SelectQuarantine get quarantine => SelectQuarantine(state);
  SelectPackages get packages => SelectPackages(state);
  SelectLinkInstall get linkInstall => SelectLinkInstall(state);
  SelectPeers get peers => SelectPeers(state);
  SelectFlows get flows => SelectFlows(state);
  SelectFlowEditor get flowEditor => SelectFlowEditor(state);
  SelectTasks get tasks => SelectTasks(state);
  SelectAssistant get assistant => SelectAssistant(state);
  SelectChanges get changes => SelectChanges(state);
  SelectHistorian get historian => SelectHistorian(state);
  SelectAccess get access => SelectAccess(state);
  SelectSystem get system => SelectSystem(state);
  SelectPanels get panels => SelectPanels(state);
}

/// Values that belong to the app rather than to one slice. They sit on the
/// facade rather than on any one substate's selectors, which is what
/// `on Selectors` says — and it is the place for a value that reads two
/// slices at once, since a `SelectX` does not reach its siblings.
///
/// It used to also hold `canEnterApp` — a token and no login in flight — which
/// nothing read: the auth guard decides on `session.isAvailable` alone, because
/// the login action writes the token in the same reduce that clears the form,
/// so "logged in and still waiting on login" is not a state anything can
/// observe. `frx graph` listed it under "nothing reaches"; now it is gone.
extension SelectComposites on Selectors {
  /// Whether any foreground operation is in flight — what the modal barrier
  /// covers.
  ///
  /// **Folded off `Wait`, not named slice by slice.** The barrier read
  /// `login.isWaiting || registration.isWaiting`, and the two features written
  /// after that line showed no loading state at all: both mix in
  /// `WaitingAction`, both have an `isWaiting` getter, and neither was in the
  /// disjunction. A list of the slices that count is a list somebody has to
  /// remember, and it was already wrong.
  ///
  /// **Keyed on `BlockingAction`, which is a claim, not a side effect.** Two
  /// narrower predicates were tried and both were too wide. `isWaitingAny` is
  /// true for any flag in `Wait`, including ones that are not actions.
  /// `isWaitingForType<WaitingAction>()` looks narrower and is not: every async
  /// action that wants an indicator mixes in `WaitingAction`, because that is
  /// what puts it in `Wait` — so the first background refresh anyone adds would
  /// blank the app.
  ///
  /// `BlockingAction` is written on purpose and means only this. The set stays
  /// a fold rather than a list: `WaitAction.add(this)` files the action as the
  /// flag and `isWaitingForType<T>` tests `flag is T`, so the mixin answers for
  /// every action carrying it and nothing here names any of them.
  bool get isBusy => state.wait.isWaitingForType<BlockingAction>();

  /// [ws] is reading again data it already shows: stale while revalidate
  /// (docs/studio.md §6.7). The workspace keeps its content and the shell
  /// lays the sweep bar over it.
  ///
  /// **Two halves, both needed.** A read of the workspace is in flight — one
  /// of the `Retrieve…` actions it dispatches when it is shown, read off
  /// `Wait` like every other `isWaiting` — *and* its slice already holds
  /// something to keep on screen. In flight with nothing held is a first
  /// load, which stays the workspace's own empty or loading state.
  ///
  /// Only reads count. A command in flight (Start, Deploy, Install, Apply)
  /// has its own busy control and is not a refresh.
  bool refreshing(Workspace ws) {
    final w = state.wait;
    return switch (ws) {
      .explorer =>
        state.nodes.table.isNotEmpty &&
            (w.isWaitingForType<RetrieveNodeDetailAction>() ||
                w.isWaitingForType<RetrieveHistoryAction>() ||
                w.isWaitingForType<RetrieveLinksAction>()),
      .links =>
        (state.links.table.isNotEmpty || state.quarantine.table.isNotEmpty) &&
            (w.isWaitingForType<RetrieveLinksAction>() ||
                w.isWaitingForType<RetrieveQuarantineAction>() ||
                w.isWaitingForType<RetrievePackagesAction>()),
      .flows =>
        state.flows.table.isNotEmpty &&
            w.isWaitingForType<RetrieveFlowsAction>(),
      .history =>
        state.historian.groups.isNotEmpty &&
            (w.isWaitingForType<RetrieveHistorianAction>() ||
                w.isWaitingForType<RetrieveSeriesAction>()),
      .access =>
        (state.access.users.isNotEmpty || state.access.grants.isNotEmpty) &&
            w.isWaitingForType<RetrieveAccessAction>(),
      .sites =>
        (state.peers.table.isNotEmpty || state.site.choices.isNotEmpty) &&
            (w.isWaitingForType<RetrievePeersAction>() ||
                w.isWaitingForType<RetrieveSitesAction>() ||
                w.isWaitingForType<RetrieveQuarantineAction>() ||
                w.isWaitingForType<RetrieveLinksAction>()),
      .assistant =>
        (state.tasks.table.isNotEmpty || state.assistant.agent != null) &&
            (w.isWaitingForType<RetrieveAgentAction>() ||
                w.isWaitingForType<RetrieveTasksAction>()),
      .system =>
        state.system.log.isNotEmpty &&
            w.isWaitingForType<RetrieveSystemLogAction>(),
    };
  }
}

extension type SelectConnectivity(AppState _state) {
  bool get isConnected => _state.connectivity.isAvailable;
}

extension type SelectLogin(AppState _state) {
  /// Returns password value
  String? get password => _state.login.password;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<LogInAction>();

  /// Returns gateway
  String? get gateway => _state.login.gateway;

  /// Returns user
  String? get user => _state.login.user;

  /// Returns step
  int get step => _state.login.step;

  /// Returns recent
  IList<String> get recent => _state.login.recent;

  /// Returns probes
  IMap<String, int> get probes => _state.login.probes;

  /// Returns remember
  bool get remember => _state.login.remember;

  /// Returns failure
  LoginFailure? get failure => _state.login.failure;

  /// Returns reason
  String? get reason => _state.login.reason;

  /// Returns isProbing
  bool get isProbing => _state.wait.isWaitingForType<ProbeGatewayAction>();

  /// Returns preload
  int get preload => _state.login.preload;

  /// Returns preloadLate
  IList<int> get preloadLate => _state.login.preloadLate;
}

extension type SelectSession(AppState _state) {
  /// Returns session token
  String? get token => _state.session.token;

  /// Returns true if session is available
  bool get isAvailable => token != null;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<LogOutAction>();
}

extension type SelectTheme(AppState _state) {
  /// Returns the selected theme mode
  ThemeMode get mode => _state.theme.mode;
}

extension type SelectLanguage(AppState _state) {
  /// Returns the selected locale code (e.g. `en`)
  String get locale => _state.language.locale;
}

extension type SelectSite(AppState _state) {
  /// Returns gateway
  String? get gateway => _state.site.gateway;

  /// Returns user
  String? get user => _state.site.user;

  /// Returns name
  String? get name => _state.site.name;

  /// Returns role
  String? get role => _state.site.role;

  /// Returns connected
  bool get connected => _state.site.connected;

  /// The site on screen: the one picked in the switcher, else the one
  /// logged into.
  String? get viewed => _state.site.current ?? _state.site.name;

  /// `wy/<viewed site>`, the root every screen's keys start from.
  String? get root => viewed == null ? null : 'wy/$viewed';

  /// `wy/<site logged into>`: where `/api/me` and the gateway live.
  String? get home =>
      _state.site.name == null ? null : 'wy/${_state.site.name}';

  /// Returns current
  String? get current => _state.site.current;

  /// Returns grants
  IList<Grant> get grants => _state.site.grants;

  /// Returns choices
  IList<SiteChoice> get choices => _state.site.choices;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveSitesAction>();

  /// The user's level on [key]: the highest grant whose pattern matches it
  /// (`none` when none does). Grants below an upstream are rewritten for
  /// the downstream site by the gateway, so the patterns are full keys.
  String levelOn(String key) {
    var best = 0;
    for (final g in _state.site.grants) {
      final r = levelRank(g.level);
      if (r > best && keyMatches(g.key, key)) {
        best = r;
      }
    }
    return levels[best];
  }

  /// The user has at least [level] on [key].
  bool can(String level, String key) =>
      levelRank(levelOn(key)) >= levelRank(level);

  /// Why a control that needs [level] on [key] is disabled, or null when the
  /// user has it (docs/studio.md §2 rule 8: shown, never hidden).
  String? needs(String level, String key) => can(level, key)
      ? null
      : 'needs $level on ${key.split('/').skip(2).join('/')}';
}

extension type SelectNodes(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveNodesAction>();

  /// Returns [IMap<String, NodeInfo>] table
  IMap<String, NodeInfo> get table => _state.nodes.table;

  /// Returns [NodeInfo] value by id
  NodeInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.nodes.view;

  /// Returns expanded
  ISet<String> get expanded => _state.nodes.expanded;

  /// Returns selectedNode
  String? get selectedNode => _state.nodes.selectedNode;

  /// Returns results
  IMap<String, IList<String>> get results => _state.nodes.results;

  /// Returns tab
  String get tab => _state.nodes.tab;

  /// Returns action
  String? get action => _state.nodes.action;

  /// Returns historyRange
  String get historyRange => _state.nodes.historyRange;

  /// Returns detail
  IMap<String, NodeDetail> get detail => _state.nodes.detail;

  /// Returns history
  IList<HistPoint> get history => _state.nodes.history;

  /// Returns historyKey
  String? get historyKey => _state.nodes.historyKey;

  /// Returns point
  String? get point => _state.nodes.point;

  /// Returns checked
  ISet<String> get checked => _state.nodes.checked;

  /// Returns anchor
  String? get anchor => _state.nodes.anchor;

  /// Returns treeFilter
  String get treeFilter => _state.nodes.treeFilter;

  /// Returns pointFilter
  String get pointFilter => _state.nodes.pointFilter;

  /// Returns marked
  ISet<String> get marked => _state.nodes.marked;

  /// Returns audit
  IList<AuditEntry> get audit => _state.nodes.audit;

  /// Returns listed
  ISet<String> get listed => _state.nodes.listed;
}

extension type SelectLive(AppState _state) {
  /// Returns values
  IMap<String, LiveValue> get values => _state.live.values;

  /// Returns watched
  IMap<String, int> get watched => _state.live.watched;
}

extension type SelectLinks(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveLinksAction>();

  /// Returns [IMap<String, LinkInfo>] table
  IMap<String, LinkInfo> get table => _state.links.table;

  /// Returns [LinkInfo] value by id
  LinkInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.links.view;

  /// Returns tab
  LinksTab get tab => _state.links.tab;

  /// Returns selectedLink
  String? get selectedLink => _state.links.selectedLink;

  /// Returns log
  IList<String> get log => _state.links.log;

  /// Returns revisions
  IList<LinkRevision> get revisions => _state.links.revisions;

  /// Returns version
  String? get version => _state.links.version;

  /// A start, stop, remove, grant, deauthorize or rollback is running.
  bool get isActing =>
      _state.wait.isWaitingForType<StartLinkAction>() ||
      _state.wait.isWaitingForType<StopLinkAction>() ||
      _state.wait.isWaitingForType<RemoveLinkAction>() ||
      _state.wait.isWaitingForType<GrantLinkAction>() ||
      _state.wait.isWaitingForType<DeauthorizeLinkAction>() ||
      _state.wait.isWaitingForType<RollbackLinkParamsAction>();

  /// The log is being read.
  bool get isReadingLog => _state.wait.isWaitingForType<GetLinkLogAction>();

  /// The parameter revisions are being read.
  bool get isReadingHistory =>
      _state.wait.isWaitingForType<RetrieveLinkHistoryAction>();
}

extension type SelectQuarantine(AppState _state) {
  /// Returns waiting value
  bool get isWaiting =>
      _state.wait.isWaitingForType<RetrieveQuarantineAction>();

  /// Returns [IMap<String, QuarantineEntry>] table
  IMap<String, QuarantineEntry> get table => _state.quarantine.table;

  /// Returns [QuarantineEntry] value by id
  QuarantineEntry byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.quarantine.view;

  /// Returns selectedEntry
  String? get selectedEntry => _state.quarantine.selectedEntry;

  /// Returns forms
  IMap<String, IList<ParamSpec>> get forms => _state.quarantine.forms;
}

extension type SelectPackages(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrievePackagesAction>();

  /// Returns [IMap<String, PackageInfo>] table
  IMap<String, PackageInfo> get table => _state.packages.table;

  /// Returns [PackageInfo] value by id
  PackageInfo byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.packages.view;
}

extension type SelectLinkInstall(AppState _state) {
  /// Returns step
  int get step => _state.linkInstall.step;

  /// Returns source
  InstallSource? get source => _state.linkInstall.source;

  /// Returns item
  String? get item => _state.linkInstall.item;

  /// Returns broker
  String? get broker => _state.linkInstall.broker;

  /// Returns mode
  LinkMode? get mode => _state.linkInstall.mode;

  /// Returns name
  String? get name => _state.linkInstall.name;

  /// Returns acceptRights
  bool get acceptRights => _state.linkInstall.acceptRights;

  /// Returns checks
  IList<PackageCheck> get checks => _state.linkInstall.checks;

  /// Returns message
  String? get message => _state.linkInstall.message;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<InstallLinkAction>();

  /// Returns path
  String get path => _state.linkInstall.path;

  /// Returns category
  String get category => _state.linkInstall.category;

  /// Returns query
  String? get query => _state.linkInstall.query;

  /// Returns phase
  String? get phase => _state.linkInstall.phase;

  /// Returns manifest
  String? get manifest => _state.linkInstall.manifest;

  /// Returns rights
  String? get rights => _state.linkInstall.rights;

  /// Returns catalog
  IList<CatalogItem> get catalog => _state.linkInstall.catalog;

  /// Returns targets
  IList<InstallTarget> get targets => _state.linkInstall.targets;

  /// Returns method
  String get method => _state.linkInstall.method;
}

extension type SelectPeers(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrievePeersAction>();

  /// Returns [IMap<String, Peer>] table
  IMap<String, Peer> get table => _state.peers.table;

  /// Returns [Peer] value by id
  Peer byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.peers.view;

  /// Returns selectedPeer
  String? get selectedPeer => _state.peers.selectedPeer;
}

extension type SelectFlows(AppState _state) {
  /// Returns search query string
  String? get query => _state.flows.query;

  /// Returns search results view
  IList<String> get view => _state.flows.view;

  /// Returns table
  IMap<String, FlowSummary> get table => _state.flows.table;

  /// Returns selectedFlow
  String? get selectedFlow => _state.flows.selectedFlow;

  /// Returns defs
  IMap<String, Object> get defs => _state.flows.defs;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveFlowsAction>();

  /// Returns blockTypes
  IList<NodeType> get blockTypes => _state.flows.blockTypes;
}

extension type SelectFlowEditor(AppState _state) {
  /// Returns flowId
  String? get flowId => _state.flowEditor.flowId;

  /// Returns draft
  FlowDraft? get draft => _state.flowEditor.draft;

  /// Returns dirty
  bool get dirty => _state.flowEditor.dirty;

  /// Returns problems
  IList<String> get problems => _state.flowEditor.problems;

  /// Returns selectedBlock
  String? get selectedBlock => _state.flowEditor.selectedBlock;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<DeployFlowAction>();

  /// Returns types
  IList<NodeType> get types => _state.flowEditor.types;

  /// Returns version
  int get version => _state.flowEditor.version;

  /// Returns state
  String? get state => _state.flowEditor.state;

  /// Returns message
  String? get message => _state.flowEditor.message;

  /// Returns palette
  String get palette => _state.flowEditor.palette;

  /// Returns ports
  IMap<String, LiveValue> get ports => _state.flowEditor.ports;

  /// Returns deployed
  FlowDraft? get deployed => _state.flowEditor.deployed;

  /// Returns watchRefused
  String? get watchRefused => _state.flowEditor.watchRefused;

  /// Returns previewPorts
  IMap<String, LiveValue> get previewPorts => _state.flowEditor.previewPorts;

  /// Returns previewSinks
  IMap<String, LiveValue> get previewSinks => _state.flowEditor.previewSinks;

  /// Returns previewError
  String? get previewError => _state.flowEditor.previewError;

  /// Returns previewOff
  String? get previewOff => _state.flowEditor.previewOff;
}

extension type SelectTasks(AppState _state) {
  /// Returns waiting value
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveTasksAction>();

  /// Returns [IMap<String, AgentTask>] table
  IMap<String, AgentTask> get table => _state.tasks.table;

  /// Returns [AgentTask] value by id
  AgentTask byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.tasks.view;

  /// Returns selectedTask
  String? get selectedTask => _state.tasks.selectedTask;

  /// Returns events
  IMap<String, IList<TaskEvent>> get events => _state.tasks.events;
}

extension type SelectAssistant(AppState _state) {
  /// Returns draft
  String? get draft => _state.assistant.draft;

  /// Returns panel
  String get panel => _state.assistant.panel;

  /// Returns agent
  String? get agent => _state.assistant.agent;

  /// Returns cfg
  IMap<String, String> get cfg => _state.assistant.cfg;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveAgentAction>();

  /// The agent is answering an ask.
  bool get isAsking => _state.wait.isWaitingForType<AskAgentAction>();
}

extension type SelectChanges(AppState _state) {
  /// Returns [IMap<String, StagedChange>] table
  IMap<String, StagedChange> get table => _state.changes.table;

  /// Returns [StagedChange] value by id
  StagedChange byId(String id) => table[id]!;

  /// Returns the ordered view of the table
  IList<String> get view => _state.changes.view;

  /// Returns open
  bool get open => _state.changes.open;

  /// Returns message
  String? get message => _state.changes.message;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<ApplyChangesAction>();
}

extension type SelectHistorian(AppState _state) {
  /// Returns groups
  IList<WatchGroup> get groups => _state.historian.groups;

  /// Returns selected
  String? get selected => _state.historian.selected;

  /// Returns range
  String get range => _state.historian.range;

  /// Returns series
  IMap<String, IList<HistPoint>> get series => _state.historian.series;

  /// Returns stats
  IMap<String, String> get stats => _state.historian.stats;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveHistorianAction>();
}

extension type SelectAccess(AppState _state) {
  /// Returns users
  IList<UserInfo> get users => _state.access.users;

  /// Returns grants
  IList<RoleGrant> get grants => _state.access.grants;

  /// Returns audit
  IList<String> get audit => _state.access.audit;

  /// Returns selected
  String? get selected => _state.access.selected;

  /// Returns tab
  String get tab => _state.access.tab;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveAccessAction>();
}

extension type SelectSystem(AppState _state) {
  /// Returns log
  IList<String> get log => _state.system.log;

  /// Returns logLevel
  String? get logLevel => _state.system.logLevel;

  /// Returns filter
  String? get filter => _state.system.filter;

  /// Returns isWaiting
  bool get isWaiting => _state.wait.isWaitingForType<RetrieveSystemLogAction>();
}

extension type SelectPanels(AppState _state) {
  /// Returns widths
  IMap<PanelSlot, double> get widths => _state.panels.widths;
}
