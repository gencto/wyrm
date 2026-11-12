import 'dart:async';

import 'package:models/node_info.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/node_info_mapper.dart';

/// What [TreeWatchService] tells its listener.
abstract class TreeWatchServiceListener {
  /// The children of [parent] as one complete list (a first read, or again
  /// after a reconnect).
  void onChildren(String parent, List<NodeInfo> children);

  /// One child of [parent] was added or changed.
  void onChild(String parent, NodeInfo child);

  /// One child of [parent] is gone.
  void onRemoved(String parent, String name);

  /// The list of [parent] failed (rights, a missing node) or ended.
  void onListError(String parent, Object error);
}

/// One live `list(key)` per open node of the tree (docs/studio.md §5.2),
/// opened by [open] and closed by [close]: everything the tree draws comes
/// from these lists, never from a one-shot read.
class TreeWatchService extends DisposableServiceInterface {
  TreeWatchService({required this._listener});

  final TreeWatchServiceListener _listener;
  WyrmApi? _api;
  final _lists = <String, StreamSubscription<ListUpdate>>{};

  /// The keys listed now.
  Set<String> get open_ => _lists.keys.toSet();

  /// Uses [api] for the lists and opens [keys].
  void attach(WyrmApi api, Iterable<String> keys) {
    _closeAll();
    _api = api;
    keys.forEach(open);
  }

  /// Lists [key] until [close]; nothing when it is listed already.
  void open(String key) {
    final api = _api;
    if (api == null || _lists.containsKey(key)) {
      return;
    }
    _lists[key] = api
        .list(key)
        .listen(
          (u) => _onUpdate(key, u),
          onError: (Object e) {
            _lists.remove(key);
            _listener.onListError(key, e);
          },
          onDone: () => _lists.remove(key),
        );
  }

  void _onUpdate(String key, ListUpdate u) {
    switch (u) {
      case ListRefreshed(:final children):
        _listener.onChildren(key, [
          for (final c in children) nodeInfoOf(key, c),
        ]);
      case ChildAdded(:final child) || ChildChanged(:final child):
        _listener.onChild(key, nodeInfoOf(key, child));
      case ChildRemoved(:final name):
        _listener.onRemoved(key, name);
      case ChildConnected() || ChildDisconnected():
        // Liveliness of a child link: its own list reports what changes.
        break;
    }
  }

  /// Stops listing [key] and every key below it.
  void close(String key) {
    for (final k in _lists.keys.toList()) {
      if (k == key || k.startsWith('$key/')) {
        unawaited(_lists.remove(k)!.cancel());
      }
    }
  }

  void _closeAll() {
    for (final s in _lists.values) {
      unawaited(s.cancel());
    }
    _lists.clear();
  }

  /// Closes every list and keeps the session (the site on screen changed).
  void detachLists() => _closeAll();

  /// Closes every list and forgets the session.
  void detach() {
    _closeAll();
    _api = null;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    detach();
  }
}
