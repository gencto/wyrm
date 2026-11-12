import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';

/// What [LiveListsService] tells its listener.
abstract class LiveListsServiceListener {
  /// The children of [parent] as one complete list (a first answer, or
  /// again after a reconnect).
  void onChildren(String parent, List<Child> children);

  /// One child of [parent] was added or changed.
  void onChild(String parent, Child child);

  /// One child of [parent] is gone.
  void onRemoved(String parent, String name);
}

/// One live `list(key)` per key a shown screen lists (History's groups and
/// the selected group's watches, the flows of `dataflows`), opened and
/// closed as the set changes ([sync]), apart from the Explorer's
/// `TreeWatchService` so neither closes the other's lists.
///
/// A list that lost its broker, or that ended, is opened again after
/// [retryEvery] while it is wanted; a refusal (rights, a missing node) is
/// final until the key is listed again.
class LiveListsService extends DisposableServiceInterface {
  LiveListsService({
    required this._listener,
    this.retryEvery = const Duration(seconds: 5),
  });

  final LiveListsServiceListener _listener;

  /// How long a list that lost its broker waits before it is opened again.
  final Duration retryEvery;

  WyrmApi? _api;
  final _want = <String>{};
  final _lists = <String, StreamSubscription<ListUpdate>>{};
  final _retries = <String, Timer>{};

  /// The keys listed now.
  Set<String> get listed => _lists.keys.toSet();

  /// Uses [api] for the lists and opens [keys].
  void attach(WyrmApi api, Iterable<String> keys) {
    _closeAll();
    _api = api;
    sync(keys);
  }

  /// Lists each key of [keys] not listed yet and closes the ones no longer
  /// in it.
  void sync(Iterable<String> keys) {
    final want = keys.toSet();
    _want
      ..clear()
      ..addAll(want);
    for (final k in _lists.keys.toList()) {
      if (!want.contains(k)) {
        unawaited(_lists.remove(k)!.cancel());
      }
    }
    for (final k in _retries.keys.toList()) {
      if (!want.contains(k)) {
        _retries.remove(k)!.cancel();
      }
    }
    if (_api == null) {
      return;
    }
    for (final k in want) {
      if (!_lists.containsKey(k) && !_retries.containsKey(k)) {
        _open(k);
      }
    }
  }

  void _open(String key) {
    final api = _api;
    if (api == null) {
      return;
    }
    _lists[key] = api
        .list(key)
        .listen(
          (u) => _onUpdate(key, u),
          onError: (Object e) {
            logger.fine('list $key: $e');
            unawaited(_lists.remove(key)?.cancel());
            if (_lost(e)) {
              _again(key);
            }
          },
          onDone: () {
            _lists.remove(key);
            _again(key);
          },
        );
  }

  void _again(String key) {
    if (!_want.contains(key)) {
      return;
    }
    _retries[key]?.cancel();
    _retries[key] = Timer(retryEvery, () {
      _retries.remove(key);
      if (_want.contains(key) && !_lists.containsKey(key)) {
        _open(key);
      }
    });
  }

  static bool _lost(Object e) => switch (e) {
    WyrmException(:final status) => switch (status.known) {
      Status.timeout ||
      Status.disconnected ||
      Status.notAvailable ||
      Status.closed => true,
      _ => false,
    },
    _ => false,
  };

  void _onUpdate(String key, ListUpdate u) {
    switch (u) {
      case ListRefreshed(:final children):
        _listener.onChildren(key, children);
      case ChildAdded(:final child) || ChildChanged(:final child):
        _listener.onChild(key, child);
      case ChildRemoved(:final name):
        _listener.onRemoved(key, name);
      case ChildConnected() || ChildDisconnected():
        break;
    }
  }

  void _closeAll() {
    for (final s in _lists.values) {
      unawaited(s.cancel());
    }
    _lists.clear();
    for (final t in _retries.values) {
      t.cancel();
    }
    _retries.clear();
  }

  /// Closes every list and forgets the session.
  void detach() {
    _closeAll();
    _api = null;
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    detach();
  }
}
