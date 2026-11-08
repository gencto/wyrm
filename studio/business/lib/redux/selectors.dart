import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:models/agent_task.dart';
import 'package:models/flow_summary.dart';
import 'package:models/install_source.dart';
import 'package:models/link_info.dart';
import 'package:models/link_mode.dart';
import 'package:models/links_tab.dart';
import 'package:models/live_value.dart';
import 'package:models/node_info.dart';
import 'package:models/package_check.dart';
import 'package:models/package_info.dart';
import 'package:models/peer.dart';
import 'package:models/quarantine_entry.dart';

import 'app_state.dart';
import 'common/action.dart';
import 'links/actions/retrieve_links_action.dart';
import 'login/actions/log_in_action.dart';
import 'nodes/actions/retrieve_nodes_action.dart';
import 'packages/actions/retrieve_packages_action.dart';
import 'peers/actions/retrieve_peers_action.dart';
import 'quarantine/actions/retrieve_quarantine_action.dart';
import 'session/actions/log_out_action.dart';
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

  /// Returns root
  String? get root =>
      _state.site.name == null ? null : 'wy/${_state.site.name}';
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
}

extension type SelectLive(AppState _state) {
  /// Returns values
  IMap<String, LiveValue> get values => _state.live.values;

  /// Returns watched
  ISet<String> get watched => _state.live.watched;
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

  /// Returns holdUnknown
  bool get holdUnknown => _state.quarantine.holdUnknown;

  /// Returns allowAll
  bool get allowAll => _state.quarantine.allowAll;

  /// Returns selectedEntry
  String? get selectedEntry => _state.quarantine.selectedEntry;
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
}

extension type SelectFlowEditor(AppState _state) {
  /// Returns flowId
  String? get flowId => _state.flowEditor.flowId;

  /// Returns draft
  Object? get draft => _state.flowEditor.draft;

  /// Returns dirty
  bool get dirty => _state.flowEditor.dirty;

  /// Returns problems
  IList<String> get problems => _state.flowEditor.problems;

  /// Returns selectedBlock
  String? get selectedBlock => _state.flowEditor.selectedBlock;
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
}

extension type SelectAssistant(AppState _state) {
  /// Returns draft
  String? get draft => _state.assistant.draft;

  /// Returns ticked
  ISet<int> get ticked => _state.assistant.ticked;

  /// Returns panel
  String get panel => _state.assistant.panel;

  /// Returns context
  IList<String> get context => _state.assistant.context;
}
