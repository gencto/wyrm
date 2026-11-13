import 'package:async_redux/async_redux.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'access/models/access_state.dart';
import 'assistant/models/assistant_state.dart';
import 'changes/models/changes_state.dart';
import 'connectivity/models/connectivity_state.dart';
import 'flow_editor/models/flow_editor_state.dart';
import 'flows/models/flows_state.dart';
import 'historian/models/historian_state.dart';
import 'language/models/language_state.dart';
import 'link_install/models/link_install_state.dart';
import 'links/models/links_state.dart';
import 'live/models/live_state.dart';
import 'login/models/login_state.dart';
import 'nodes/models/nodes_state.dart';
import 'packages/models/packages_state.dart';
import 'panels/models/panels_state.dart';
import 'peers/models/peers_state.dart';
import 'problems/models/problems_state.dart';
import 'quarantine/models/quarantine_state.dart';
import 'session/models/session_state.dart';
import 'site/models/site_state.dart';
import 'system/models/system_state.dart';
import 'tasks/models/tasks_state.dart';
import 'theme/models/theme_state.dart';
import 'views/models/views_state.dart';
import 'window/models/window_state.dart';

export 'selectors.dart';

part 'app_state.freezed.dart';

@freezed
abstract class AppState with _$AppState {
  const factory AppState({
    required ConnectivityState connectivity,
    required LoginState login,
    required SessionState session,
    required ThemeState theme,
    required LanguageState language,
    required SiteState site,
    required NodesState nodes,
    required LiveState live,
    required LinksState links,
    required QuarantineState quarantine,
    required PackagesState packages,
    required LinkInstallState linkInstall,
    required PeersState peers,
    required FlowsState flows,
    required FlowEditorState flowEditor,
    required TasksState tasks,
    required AssistantState assistant,
    required ChangesState changes,
    required HistorianState historian,
    required AccessState access,
    required SystemState system,
    required PanelsState panels,
    required WindowState window,
    required ProblemsState problems,
    required ViewsState views,
    required Wait wait,
  }) = _AppState;

  factory AppState.initial() => const AppState(
    connectivity: ConnectivityState(),
    login: LoginState(),
    session: SessionState(),
    theme: ThemeState(),
    language: LanguageState(),
    site: SiteState(),
    nodes: NodesState(),
    live: LiveState(),
    links: LinksState(),
    quarantine: QuarantineState(),
    packages: PackagesState(),
    linkInstall: LinkInstallState(),
    peers: PeersState(),
    flows: FlowsState(),
    flowEditor: FlowEditorState(),
    tasks: TasksState(),
    assistant: AssistantState(),
    changes: ChangesState(),
    historian: HistorianState(),
    access: AccessState(),
    system: SystemState(),
    panels: PanelsState(),
    window: WindowState(),
    problems: ProblemsState(),
    views: ViewsState(),
    wait: Wait.empty,
  );
}
