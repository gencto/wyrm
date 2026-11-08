import 'package:async_redux/async_redux.dart';
import 'package:storage/storage.dart';
import 'package:wyrm_client/wyrm_client.dart';

import 'redux/app_state.dart';
import 'redux/services/connectivity/connectivity.dart';
import 'redux/services/connectivity/connectivity_dispatcher.dart';
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
  AppDependencies(this._store, this.settings, {WyrmLogin? login})
    : login = login ?? const GatewayLogin();

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

  /// The broker API of the session (docs/studio.md §5.3). Throws a
  /// [UserException] when nobody is logged in, so an action dispatched after a
  /// log out fails visibly instead of with a null error.
  WyrmApi get wyrm =>
      _session?.api ??
      (throw const UserException('Not connected to a gateway.'));

  /// Keeps [session] as the one in use; closes the one it replaces.
  Future<void> attach(WyrmSession session) async {
    final old = _session;
    _session = session;
    if (old != null && !identical(old, session)) {
      await old.close();
    }
  }

  /// Closes the session in use, if any.
  Future<void> detach() async {
    final old = _session;
    _session = null;
    await old?.close();
  }

  late final connectivity = ConnectivityService(
    listener: ConnectivityDispatcher(store: _store),
  );

  /// Runs the async service initialization. Call once, right after the store
  /// is created (see `run_env.dart`).
  Future<void> warmUp() async {
    await connectivity.start();
  }
}
