// A client that outlives its connection. The gateway closes every WebSocket
// when the broker rebuilds its router (an ACL change: a link installed, a
// site authorized or held in quarantine, ADR 0006), and networks drop.

import 'dart:async';

import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';
import 'frames.dart';

/// [WyrmApi] that opens a new connection when one is lost and opens its
/// live streams again on it: a `list` starts over with [ListRefreshed], a
/// `subscribe` with the stored values.
///
/// Reads (`meta`, `children`, `history`) wait for the connection and go
/// again when it is lost under them. A `set` or an `invoke` made while
/// disconnected waits; one cut by a lost connection fails, as it may or may
/// not have run. A connect refused with `permission_denied` (the login
/// session expired or was revoked) ends the client: every stream and call
/// gets that error.
class ReconnectingClient implements WyrmApi {
  final Future<FrameClient> Function() _connect;

  /// Longest wait for a connection in a call; streams wait without limit.
  final Duration callWait;

  /// Longest pause between two connect attempts.
  final Duration maxDelay;

  FrameClient? _c;
  Completer<FrameClient>? _next;
  WyrmException? _fatal;
  bool _closed = false;
  bool _shut = false;
  final _state = StreamController<bool>.broadcast();

  ReconnectingClient._(this._connect, this.callWait, this.maxDelay);

  /// Connect once (its error is thrown here), then keep a connection.
  static Future<ReconnectingClient> open(
    Future<FrameClient> Function() connect, {
    Duration callWait = const Duration(seconds: 30),
    Duration maxDelay = const Duration(seconds: 5),
  }) async {
    final r = ReconnectingClient._(connect, callWait, maxDelay);
    r._attach(await connect());
    return r;
  }

  bool get isConnected => _c != null;

  /// `false` when the connection is lost, `true` when a new one is up.
  Stream<bool> get connection => _state.stream;

  void _attach(FrameClient c) {
    _c = c;
    _state.add(true);
    final n = _next;
    _next = null;
    n?.complete(c);
    c.done.then((_) => _lost(c));
  }

  void _lost(FrameClient c) {
    if (!identical(_c, c) || _closed) return;
    _c = null;
    _state.add(false);
    _reconnect();
  }

  Future<void> _reconnect() async {
    const first = Duration(milliseconds: 200);
    var delay = first < maxDelay ? first : maxDelay;
    while (!_closed) {
      try {
        final c = await _connect();
        if (_closed) {
          await c.close();
          return;
        }
        _attach(c);
        return;
      } on WyrmException catch (e) {
        if (e.status == StatusCode.of(Status.permissionDenied)) {
          _end(e);
          return;
        }
      } catch (_) {
        // refused or reset while the broker comes back: try again
      }
      await Future<void>.delayed(delay);
      delay = delay * 2 > maxDelay ? maxDelay : delay * 2;
    }
  }

  void _end(WyrmException e) {
    _fatal ??= e;
    _closed = true;
    final n = _next;
    _next = null;
    n?.completeError(e);
    n?.future.ignore();
  }

  WyrmException get _gone => _fatal ?? WyrmException.of(Status.disconnected, 'client closed');

  /// The live connection, or the next one.
  Future<FrameClient> _client() {
    if (_closed) return Future.error(_gone);
    final c = _c;
    if (c != null && !c.isClosed) return Future.value(c);
    if (c != null) _lost(c);
    return (_next ??= Completer<FrameClient>()).future;
  }

  /// [_client] for a call: at most [callWait].
  Future<FrameClient> _ready() => _client().timeout(callWait,
      onTimeout: () => throw WyrmException.of(Status.disconnected, 'not connected'));

  /// A read: again on the next connection when this one is lost under it.
  Future<T> _read<T>(Future<T> Function(FrameClient c) f) async {
    while (true) {
      final c = await _ready();
      try {
        return await f(c);
      } on WyrmException {
        if (!c.isClosed) rethrow;
      }
    }
  }

  /// A live stream: open again on each new connection until it ends by
  /// itself, fails, or is cancelled.
  Stream<T> _live<T>(Stream<T> Function(FrameClient c) open) {
    late final StreamController<T> ctl;
    StreamSubscription<T>? sub;
    Completer<void>? ended;
    var cancelled = false;
    Future<void> run() async {
      while (!cancelled) {
        final FrameClient c;
        try {
          c = await _client();
        } on WyrmException catch (e) {
          if (!cancelled) ctl.addError(e);
          break;
        }
        if (cancelled) break;
        final end = ended = Completer<void>();
        sub = open(c).listen(
          ctl.add,
          onError: (Object e, StackTrace st) {
            if (!c.isClosed) ctl.addError(e, st); // else: open it again
          },
          onDone: () {
            if (!end.isCompleted) end.complete();
          },
        );
        await end.future;
        sub = null;
        if (!c.isClosed) break; // it ended by itself
      }
      if (!cancelled) await ctl.close();
    }

    ctl = StreamController<T>(
      onListen: run,
      onCancel: () {
        cancelled = true;
        final e = ended;
        if (e != null && !e.isCompleted) e.complete();
        return sub?.cancel();
      },
    );
    return ctl.stream;
  }

  @override
  Stream<ListUpdate> list(String key) => _live((c) => c.list(key));

  @override
  Stream<ValEvent> subscribe(String pattern) => _live((c) => c.subscribe(pattern));

  /// The error of a request cut by a lost connection.
  static WyrmException _cut(FrameClient c, WyrmException e) => c.isClosed
      ? WyrmException.of(Status.disconnected, 'connection lost: the request may have run')
      : e;

  @override
  Future<void> set(String key, Value value) async {
    final c = await _ready();
    try {
      await c.set(key, value);
    } on WyrmException catch (e) {
      throw _cut(c, e);
    }
  }

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) async* {
    final c = await _ready();
    try {
      yield* c.invoke(key, action, args);
    } on WyrmException catch (e) {
      throw _cut(c, e);
    }
  }

  @override
  Future<NodeMeta> meta(String key) => _read((c) => c.meta(key));

  @override
  Future<List<Child>> children(String key) => _read((c) => c.children(key));

  @override
  Future<List<HistRow>> history(String key,
          {required String from, String to = '', String? agg, String? window, int? limit}) =>
      _read((c) => c.history(key, from: from, to: to, agg: agg, window: window, limit: limit));

  @override
  Future<void> close() async {
    if (_shut) return;
    _shut = true;
    _end(WyrmException.of(Status.disconnected, 'client closed'));
    final c = _c;
    _c = null;
    await c?.close();
    // not awaited: a broadcast close waits for every listener
    unawaited(_state.close());
  }
}
