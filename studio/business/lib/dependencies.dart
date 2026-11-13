import 'dart:async';

import 'package:async_redux/async_redux.dart';
import 'package:models/error_kind.dart';
import 'package:models/studio_error.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'redux/app_state.dart';
import 'redux/links/actions/retrieve_links_action.dart';
import 'redux/packages/actions/retrieve_packages_action.dart';
import 'redux/quarantine/actions/retrieve_quarantine_action.dart';
import 'redux/services/agent_tasks/agent_tasks.dart';
import 'redux/services/agent_tasks/agent_tasks_dispatcher.dart';
import 'redux/services/connectivity/connectivity.dart';
import 'redux/services/connectivity/connectivity_dispatcher.dart';
import 'redux/services/flow_preview/flow_preview.dart';
import 'redux/services/flow_preview/flow_preview_dispatcher.dart';
import 'redux/services/flow_watch/flow_watch.dart';
import 'redux/services/flow_watch/flow_watch_dispatcher.dart';
import 'redux/services/live_lists/live_lists.dart';
import 'redux/services/live_lists/live_lists_dispatcher.dart';
import 'redux/services/live_values/live_values.dart';
import 'redux/services/live_values/live_values_dispatcher.dart';
import 'redux/services/traffic/traffic.dart';
import 'redux/services/traffic/traffic_dispatcher.dart';
import 'redux/services/tree_watch/tree_watch.dart';
import 'redux/services/tree_watch/tree_watch_dispatcher.dart';
import 'redux/services/view_bridge/view_bridge.dart';
import 'redux/services/view_bridge/view_bridge_dispatcher.dart';
import 'redux/services/wyrm_connection/wyrm_connection.dart';
import 'redux/services/wyrm_connection/wyrm_connection_dispatcher.dart';
import 'wyrm/failures.dart';
import 'wyrm/session.dart';

/// Container for the app's injected services, one instance per [Store].
///
/// Wired via the store's `dependencies` factory, which receives the store — so
/// services that need to dispatch (like connectivity) are built here without a
/// circular dependency. Services are lazy (`late final`); [warmUp] runs the
/// async setup the synchronous factory can't do itself.
///
/// Access it from actions via the `deps` getter on the base `Action`.
class AppDependencies {
  AppDependencies(
    this._store,
    this.settings, {
    WyrmLogin? login,
    ErrorWording? wording,
  }) : login = login ?? const GatewayLogin(),
       wording = wording ?? plainWording;

  /// The words of an error: its title and, for a fault in Studio, its
  /// sentence. The app's, in the user's language; plain English in tests.
  final ErrorWording wording;

  final Store<AppState> _store;

  /// Storage backend, opened once in run_env and shared with the Persistor.
  ///
  /// Typed on the interface, not on `KeyValueStorage`: the concrete adapter
  /// reaches path_provider, so a consumer naming it cannot be built without a
  /// Flutter binding and a real file.
  final BaseKeyValueStorage settings;

  /// How a session is opened. Tests pass a fake.
  final WyrmLogin login;

  WyrmSession? _session;

  /// The logged-in gateway session, or null before a login.
  WyrmSession? get session => _session;

  /// The broker API of the session (docs/studio.md §5.3). Throws a `reach`
  /// error when nobody is logged in, so an action dispatched after a log out
  /// fails visibly instead of with a null error.
  WyrmApi get wyrm =>
      _session?.api ??
      (throw StudioException(
        const StudioError(
          kind: ErrorKind.reach,
          message: 'Studio is not connected to a gateway.',
        ),
      ));

  /// Keeps [session] as the one in use and points every service at it;
  /// closes the one it replaces.
  Future<void> attach(WyrmSession session) async {
    final old = _session;
    _session = session;
    connection.attach(session.connection);
    liveValues.attach(session.api, _store.state.live.watched.keys);
    treeWatch.attach(session.api, _store.state.nodes.expanded);
    liveLists.attach(session.api, _store.state.live.lists.keys);
    agentTasks.attach(session.api);
    flowWatch.attach(session.api);
    flowPreview.attach(session.api);
    viewBridge.attach(session.api);
    if (old != null && !identical(old, session)) {
      await old.close();
    }
  }

  /// Stops every service's subscriptions and closes the session in use.
  Future<void> detach() async {
    final old = _session;
    _session = null;
    await connection.detach();
    liveValues.detach();
    treeWatch.detach();
    liveLists.detach();
    agentTasks.detach();
    flowWatch.detach();
    flowPreview.detach();
    viewBridge.detach();
    await old?.close();
  }

  /// Reads that run again after the gateway socket is back (each screen adds
  /// its Retrieve action here, docs/studio.md §5.2).
  final reloads = <void Function(Store<AppState> store)>[
    (store) {
      if (store.state.links.view.isNotEmpty) {
        unawaited(store.dispatchAndWait(RetrieveLinksAction()));
      }
      if (store.state.quarantine.view.isNotEmpty) {
        unawaited(store.dispatchAndWait(RetrieveQuarantineAction()));
      }
      if (store.state.packages.view.isNotEmpty) {
        unawaited(store.dispatchAndWait(RetrievePackagesAction()));
      }
    },
  ];

  /// `site.connected` from the client's socket.
  late final connection = WyrmConnectionService(
    listener: WyrmConnectionDispatcher(
      store: _store,
      onReconnect: (store) {
        for (final reload in reloads) {
          reload(store);
        }
      },
    ),
  );

  /// One subscription per key on screen, batched every 200 ms.
  late final liveValues = LiveValuesService(
    listener: LiveValuesDispatcher(store: _store),
  );

  /// One live list per open tree node.
  late final treeWatch = TreeWatchService(
    listener: TreeWatchDispatcher(store: _store),
  );

  /// One live list per key a shown screen lists (`live.lists`): History's
  /// groups and watches, the flows of `dataflows`.
  late final liveLists = LiveListsService(
    listener: LiveListsDispatcher(store: _store),
  );

  /// The task states of the agent link in use.
  late final agentTasks = AgentTasksService(
    listener: AgentTasksDispatcher(store: _store),
  );

  /// The live values of the flow open in the editor (ADR 0038 §3).
  late final flowWatch = FlowWatchService(
    listener: FlowWatchDispatcher(store: _store),
  );

  /// The live values of the draft being edited (`dataflows` ▸ `preview`).
  late final flowPreview = FlowPreviewService(
    listener: FlowPreviewDispatcher(store: _store),
  );

  /// The values, lists and meta of the view on screen in the views lab
  /// (docs/design/specs/genui-views.md).
  late final viewBridge = ViewBridgeService(
    listener: ViewBridgeDispatcher(store: _store),
  );

  late final traffic = TrafficService(
    listener: TrafficDispatcher(store: _store),
  );

  late final connectivity = ConnectivityService(
    listener: ConnectivityDispatcher(store: _store),
  );

  /// Runs the async service initialization. Call once, right after the store
  /// is created (see `run_env.dart`).
  Future<void> warmUp() async {
    await connectivity.start();
    await connection.start();
    await liveValues.start();
    await treeWatch.start();
    await liveLists.start();
    await agentTasks.start();
    await flowWatch.start();
    await flowPreview.start();
    await traffic.start();
    await viewBridge.start();
  }
}
