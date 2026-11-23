import 'dart:async';
import 'dart:io';

import 'package:async_redux/async_redux.dart';
import 'package:logging/logging.dart';
import 'package:storage/storage.dart';

import '../dependencies.dart';
import '../environment.dart';
import '../persistor.dart';
import '../wyrm/device_keys.dart';
import '../wyrm/failures.dart';
import 'app_state.dart';

late Store<AppState>? _store;

Store<AppState> newStore({
  required DevicePrompts prompts,
  required Environment environment,
  required AppState initialState,
  required BaseKeyValueStorage settings,
  Persistor<AppState>? persistor,
}) {
  _store = Store<AppState>(
    initialState: initialState,
    environment: environment,
    dependencies: (store) => AppDependencies(store, settings, prompts: prompts),
    persistor: persistor,
    globalErrorObserver: (store) => _MyErrorObserver(),
    actionObservers: [_ReduxActionLogger()],
    stateObservers: [_StateChangeObserver()],
    modelObserver: _DefaultModelObserver<dynamic>(),
  );

  return _store!;
}

/// The file Studio keeps its own settings in, in the documents directory.
const settingsFile = 'settings.db';

/// Studio's own storage did not open (docs/design/specs/errors.md §6): the
/// one condition the start screen is for.
final class StorageFault implements Exception {
  const StorageFault(this.error, this.stack, this.path);

  /// What the storage threw.
  final Object error;
  final StackTrace stack;

  /// The file that did not open, when the storage got as far as naming it.
  final String? path;

  @override
  String toString() => 'StorageFault(${faultLine(error)})';
}

/// Opens the settings storage; a failure is a [StorageFault]. [directory]
/// replaces the documents directory (tests).
Future<KeyValueStorage> openSettings({String? directory}) async {
  final settings = KeyValueStorage();
  try {
    await settings.setupStorage(dbFile: settingsFile, directory: directory);
  } on Object catch (e, st) {
    throw StorageFault(e, st, settings.path);
  }
  return settings;
}

/// *Start with fresh settings*: moves the unreadable file at [path] aside as
/// `<name>.broken` (an older `.broken` is replaced) and returns the new
/// path. The next [openSettings] then starts from nothing; the old file
/// stays for whoever wants to look into it.
Future<String> setAsideSettings(String path) async {
  final kept = '$path.broken';
  final old = File(kept);
  if (old.existsSync()) {
    await old.delete();
  }
  await File(path).rename(kept);
  return kept;
}

/// Full boot for the app layer: opens storage, wires the [AppPersistor],
/// restores the last persisted state, and builds the store. Keeps the storage
/// backend inside `business` — the app never touches it.
///
/// [prompts] are the words of the device key's OS prompts. They are the
/// app's (`ui`'s) to supply: `business` never names `S`, so the arrow
/// between the two packages keeps pointing one way. An error holds no
/// words of Studio's at all: `ui` says them when it draws one.
///
/// Throws a [StorageFault] when the settings do not open or do not read;
/// `run_env.dart` then shows the start screen instead of the app.
Future<Store<AppState>> createStore(
  Environment environment, {
  required DevicePrompts prompts,
  String? directory,
}) async {
  final settings = await openSettings(directory: directory);

  final persistor = AppPersistor(settings);
  final AppState initialState;
  try {
    initialState = await persistor.readState() ?? AppState.initial();
  } on Object catch (e, st) {
    throw StorageFault(e, st, settings.path);
  }

  return newStore(
    environment: environment,
    initialState: initialState,
    settings: settings,
    persistor: persistor,
    prompts: prompts,
  );
}

/// Logs every failure and makes sure it leaves as a [StudioException].
///
/// Every action of Studio, in `business` and in `app`, extends `Action`: it
/// wraps its own failure in `Action.wrapError` and adds it to Problems in
/// its own `after`, so what arrives here is finished and only logged. The
/// observer dispatches nothing.
class _MyErrorObserver extends GlobalErrorObserver<AppState> {
  final _logger = Logger('Redux');

  @override
  Object? observe() {
    final e = error;
    if (e is StudioException) {
      _logger.shout('${action.runtimeType} failed: $e');
      return e;
    }
    // Every action of Studio extends `Action`
    // (`redux/common/action.dart`): it wraps its own failure into a
    // [StudioException] and adds it to Problems in its `after()`. What
    // reaches here unwrapped is not one of them; it is logged and wrapped
    // for whoever awaits it, and nothing is dispatched from an observer.
    final thrown = studioExceptionOf(
      e,
      stackTrace,
      step: '${action.runtimeType}',
    );
    _logger.shout('${action.runtimeType} failed: $thrown');
    return thrown;
  }
}

/// One in-flight dispatch, keyed by the action instance — stable across nested
/// dispatches that would otherwise bump the global dispatchCount mid-action.
/// Lets the action logger print duration + the state diff on the action's line.
final _pending = <ReduxAction<AppState>, _PendingAction>{};

class _PendingAction {
  _PendingAction(ReduxAction<AppState> action)
    : stopwatch = Stopwatch()..start(),
      isSync = action.isSync();

  final Stopwatch stopwatch;
  final bool isSync;
  List<String> changed = const [];
}

class _ReduxActionLogger extends ActionObserver<AppState> {
  final _logger = Logger('Redux');

  @override
  void observe(
    ReduxAction<AppState> action,
    int dispatchCount, {
    bool ini = false,
  }) {
    if (ini) {
      _pending[action] = _PendingAction(action);
      return;
    }

    // On end, one line: action, sync/async, duration, and the state diff
    // collected by _StateChangeObserver during this dispatch.
    final pending = _pending.remove(action);
    final kind = (pending?.isSync ?? true) ? 'sync' : 'async';
    final ms = ((pending?.stopwatch.elapsedMicroseconds ?? 0) / 1000)
        .toStringAsFixed(1);
    final changed = pending?.changed ?? const <String>[];
    final diff = changed.isEmpty ? '' : '  Δ ${changed.join(', ')}';
    _logger.info('${action.runtimeType}  #$dispatchCount  $kind ${ms}ms$diff');
  }
}

/// Records which top-level [AppState] substates an action changed into
/// [_pending], for the action logger to print.
class _StateChangeObserver implements StateObserver<AppState> {
  @override
  void observe(
    ReduxAction<AppState> action,
    AppState prev,
    AppState next,
    Object? error,
    int dispatchCount,
  ) {
    final pending = _pending[action];
    if (pending == null || error != null || identical(prev, next)) {
      return;
    }

    pending.changed = <String>[
      if (prev.connectivity != next.connectivity) 'connectivity',
      if (prev.login != next.login) 'login',
      if (prev.session != next.session) 'session',
      if (prev.theme != next.theme) 'theme',
      if (prev.language != next.language) 'language',
      if (prev.site != next.site) 'site',
      if (prev.nodes != next.nodes) 'nodes',
      if (prev.live != next.live) 'live',
      if (prev.links != next.links) 'links',
      if (prev.quarantine != next.quarantine) 'quarantine',
      if (prev.packages != next.packages) 'packages',
      if (prev.linkInstall != next.linkInstall) 'linkInstall',
      if (prev.peers != next.peers) 'peers',
      if (prev.flows != next.flows) 'flows',
      if (prev.flowEditor != next.flowEditor) 'flowEditor',
      if (prev.tasks != next.tasks) 'tasks',
      if (prev.assistant != next.assistant) 'assistant',
      if (prev.changes != next.changes) 'changes',
      if (prev.historian != next.historian) 'historian',
      if (prev.access != next.access) 'access',
      if (prev.system != next.system) 'system',
      if (prev.panels != next.panels) 'panels',
      if (prev.window != next.window) 'window',
      if (prev.problems != next.problems) 'problems',
      if (prev.updates != next.updates) 'updates',
      if (prev.backups != next.backups) 'backups',
      if (prev.brokerUpdate != next.brokerUpdate) 'brokerUpdate',
      if (prev.device != next.device) 'device',
      if (prev.discovery != next.discovery) 'discovery',
      if (prev.clock != next.clock) 'clock',
    ];
  }
}

/// Logs each connector that actually rebuilt, tagged by #N (its action).
class _DefaultModelObserver<Model> implements ModelObserver<Model> {
  final _logger = Logger('Redux');

  @override
  void observe({
    required Model? modelPrevious,
    required Model? modelCurrent,
    bool? isDistinct,
    StoreConnectorInterface<dynamic, dynamic>? storeConnector,
    int? reduceCount,
    int? dispatchCount,
  }) {
    // Skip connectors that didn't rebuild.
    if (isDistinct != true) {
      return;
    }

    final name =
        (storeConnector?.debug == null ? storeConnector : storeConnector!.debug)
            .runtimeType;
    _logger.info('  ↻ $name  #$dispatchCount');
  }
}
