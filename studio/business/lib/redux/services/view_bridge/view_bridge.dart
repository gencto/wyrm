import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/values.dart';
import '../../../wyrm/views/view_doc.dart';

/// Where the unit and the decimals of a key's `~meta` are written in a
/// surface's data model: `/~meta/<escaped key>/{unit,decimals}`. A root of
/// its own, so it never collides with a value at `/<key>`.
const viewMetaRoot = '~meta';

/// Where a quality other than good is written: `/~q/<escaped key>`
/// (`uncertain`, `bad`, or `none` for a key that cannot be read).
const viewQualityRoot = '~q';

/// [key] as one JSON-pointer segment.
String escapeKey(String key) => key.replaceAll('~', '~0').replaceAll('/', '~1');

/// What [ViewBridgeService] tells its listener.
abstract class ViewBridgeServiceListener {
  /// Data-model writes since the last call: path → value, null removes
  /// what is at the path. At most every [ViewBridgeService.flushEvery].
  void onData(Map<String, Object?> changed);

  /// What the broker said about keys the view reads: key → `ok`, or the
  /// wire name of the status that refused it (`not_found`, …).
  void onKeys(Map<String, String> states);

  /// The children of [key], a node the project's menu lists.
  void onChildren(String key, List<String> names);
}

/// Feeds the data model of one genui surface from the broker
/// (docs/design/specs/genui-views.md §3.1): one `subscribe` per key the
/// document reads, one live `list` per `~children` template (a child added
/// or removed adds or removes an instance), the unit and decimals of each
/// key from its `~meta`. It knows nothing of genui: it emits path → value
/// writes, and whoever owns the surface applies them.
class ViewBridgeService extends DisposableServiceInterface {
  ViewBridgeService({
    required this._listener,
    this.flushEvery = const Duration(milliseconds: 100),
  });

  final ViewBridgeServiceListener _listener;

  /// How often buffered writes are handed over.
  final Duration flushEvery;

  WyrmApi? _api;
  var _bindings = const ViewBindings();
  Set<String> _menu = const {};
  Map<String, Object?> _root = const {};

  final _subs = <String, StreamSubscription<ValEvent>>{};
  final _lists = <String, StreamSubscription<ListUpdate>>{};
  final _children = <String, Map<String, String>>{};
  final _routes = <String, Set<String>>{};
  final _values = <String, (Object?, String?)>{};
  final _meta = <String, (String?, int?)>{};
  final _asked = <String>{};
  final _pending = <String, Object?>{};
  final _states = <String, String>{};
  Timer? _timer;

  /// The keys subscribed now.
  Set<String> get subscribed => _subs.keys.toSet();

  /// Uses [api] for everything opened from now on.
  void attach(WyrmApi api) {
    _closeAll();
    _api = api;
    _apply();
  }

  /// Shows [bindings]: opens what they read and closes the rest. [menu] are
  /// nodes whose children the project's menu lists; [root] is written at
  /// the root of the data model (`$name`, `$key` of a page's parameter).
  void sync(
    ViewBindings bindings, {
    Set<String> menu = const {},
    Map<String, Object?> root = const {},
  }) {
    _bindings = bindings;
    _menu = menu;
    _root = root;
    _apply();
  }

  void _apply() {
    final api = _api;
    if (api == null) {
      return;
    }
    // Lists first: a template's routes come from its children.
    final lists = {..._menu, for (final t in _bindings.templates) t.listKey};
    for (final k in _lists.keys.toList()) {
      if (!lists.contains(k)) {
        unawaited(_lists.remove(k)!.cancel());
        _children.remove(k);
      }
    }
    for (final k in lists) {
      _lists[k] ??= api
          .list(k)
          .listen(
            (u) => _onList(k, u),
            onError: (Object e) {
              logger.fine('list $k: $e');
              unawaited(_lists.remove(k)?.cancel());
              _state(k, _status(e));
            },
          );
    }
    _route();
  }

  /// Recomputes key → paths, opens and closes subscriptions to match, and
  /// writes again what is already known.
  void _route() {
    final api = _api;
    if (api == null) {
      return;
    }
    final routes = <String, Set<String>>{};
    void add(String key, String path) =>
        routes.putIfAbsent(key, () => {}).add(path);
    for (final k in _bindings.keys) {
      add(k, '/$k');
    }
    _root.forEach((k, v) => _pending['/$k'] = v);
    for (final t in _bindings.templates) {
      for (final MapEntry(key: name, value: display)
          in (_children[t.listKey] ?? const <String, String>{}).entries) {
        final child = '${t.listKey}/$name';
        _pending['${t.path}/$name/\$name'] = display;
        _pending['${t.path}/$name/\$key'] = child;
        for (final rel in t.rel) {
          add('$child/$rel', '${t.path}/$name/$rel');
        }
        for (final rel in t.targets) {
          _ask(rel.isEmpty ? child : '$child/$rel');
        }
      }
    }
    _routes
      ..clear()
      ..addAll(routes);
    for (final k in _subs.keys.toList()) {
      if (!routes.containsKey(k)) {
        unawaited(_subs.remove(k)!.cancel());
        _values.remove(k);
      }
    }
    for (final k in routes.keys) {
      _subs[k] ??= api
          .subscribe(k)
          .listen(
            _onValue,
            onError: (Object e) {
              logger.fine('subscribe $k: $e');
              unawaited(_subs.remove(k)?.cancel());
              _state(k, _status(e));
              _pending['/$viewQualityRoot/${escapeKey(k)}'] = 'none';
              _schedule();
            },
          );
      _ask(k);
      if (_values[k] case (final v, final q)?) {
        _write(k, v, q);
      }
      if (_meta[k] case final m?) {
        _writeMeta(k, m);
      }
    }
    _schedule();
  }

  void _onList(String key, ListUpdate u) {
    final now = _children.putIfAbsent(key, () => {});
    final before = now.keys.toSet();
    switch (u) {
      case ListRefreshed(:final children):
        now
          ..clear()
          ..addAll({
            for (final c in children)
              if (_isNode(c)) c.name: _display(c),
          });
        _state(key, 'ok');
      case ChildAdded(:final child) || ChildChanged(:final child):
        if (!_isNode(child)) {
          return;
        }
        now[child.name] = _display(child);
      case ChildRemoved(:final name):
        now.remove(name);
      case ChildConnected() || ChildDisconnected():
        return;
    }
    for (final gone in before.difference(now.keys.toSet())) {
      for (final t in _bindings.templates) {
        if (t.listKey == key) {
          _pending['${t.path}/$gone'] = null;
        }
      }
    }
    if (_menu.contains(key)) {
      _listener.onChildren(key, now.keys.toList());
    }
    _route();
  }

  static String _display(Child c) => c.meta.display ?? c.name;

  /// A child that is a node, not a value: the children of a device folder
  /// are its devices, not its `status` and `requests` points.
  static bool _isNode(Child c) => c.meta.ty == null;

  void _onValue(ValEvent e) {
    switch (e) {
      case ValSample(:final key, :final sample):
        final q = switch (sample.q) {
          Quality.good => null,
          Quality.uncertain => 'uncertain',
          Quality.bad => 'bad',
        };
        final v = toDart(sample.v);
        _values[key] = (v, q);
        _write(key, v, q);
      case ValRemoved(:final key):
        _values.remove(key);
        _write(key, null, 'none');
    }
    _schedule();
  }

  void _write(String key, Object? v, String? q) {
    for (final path in _routes[key] ?? const <String>{}) {
      _pending[path] = v;
    }
    _pending['/$viewQualityRoot/${escapeKey(key)}'] = q;
  }

  void _writeMeta(String key, (String?, int?) m) {
    final at = '/$viewMetaRoot/${escapeKey(key)}';
    _pending['$at/unit'] = m.$1;
    _pending['$at/decimals'] = m.$2;
  }

  /// Reads the `~meta` of [key] once: whether it exists, its unit and
  /// decimals.
  void _ask(String key) {
    final api = _api;
    if (api == null || !_asked.add(key)) {
      return;
    }
    unawaited(
      api
          .meta(key)
          .then((m) {
            final meta = (m.unit?.toString(), integer(attrOf(m, 'precision')));
            _meta[key] = meta;
            _state(key, 'ok');
            if (_routes.containsKey(key)) {
              _writeMeta(key, meta);
              _schedule();
            }
          })
          .catchError((Object e) {
            _asked.remove(key);
            _state(key, _status(e));
            if (_routes.containsKey(key)) {
              _pending['/$viewQualityRoot/${escapeKey(key)}'] = 'none';
              _schedule();
            }
          }),
    );
  }

  static String _status(Object e) => switch (e) {
    WyrmException(:final status) => status.name,
    _ => 'failed',
  };

  void _state(String key, String state) {
    if (_states[key] != state) {
      _states[key] = state;
      _listener.onKeys({key: state});
    }
  }

  void _schedule() {
    if (_pending.isNotEmpty) {
      _timer ??= Timer(flushEvery, flush);
    }
  }

  /// Hands the buffered writes to the listener now.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final batch = Map.of(_pending);
    _pending.clear();
    _listener.onData(batch);
  }

  void _closeAll() {
    for (final s in _subs.values) {
      unawaited(s.cancel());
    }
    for (final s in _lists.values) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _lists.clear();
    _children.clear();
    _routes.clear();
    _values.clear();
    _meta.clear();
    _asked.clear();
    _states.clear();
    _pending.clear();
    _timer?.cancel();
    _timer = null;
  }

  /// Closes everything the view opened; the session stays.
  void close() {
    _closeAll();
    _bindings = const ViewBindings();
    _menu = const {};
    _root = const {};
  }

  /// Closes everything and forgets the session.
  void detach() {
    close();
    _api = null;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    detach();
  }
}
