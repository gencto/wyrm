// The frame protocol of the gateway WebSocket (crates/wyrm-gateway/src/ws.rs),
// shared by every transport:
//
// client → server: `{id, op, key, value?, action?, args?, sub?}`
// server → client: `{id, ok: true, result?}` | `{id, ok: false, error: {status, message}}`
//                  `{id, event: {type, …}}`

import 'dart:async';
import 'dart:typed_data';

import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';

/// Carries frames. [send] takes the logical request map; the transport
/// encodes it (CBOR over a WebSocket, or a call into the FFI library).
abstract interface class FrameTransport {
  /// Decoded server frames. Done = the connection is gone.
  Stream<Value> get incoming;

  void send(Map<String, Value> frame);

  Future<void> close();
}

/// [WyrmApi] over a [FrameTransport].
/// One invoke outside the frame transport: `(key, action, args)` → the last
/// result. For arguments larger than a frame ([maxFrameArgs]).
typedef BulkInvoke = Future<Value> Function(String key, String action, Value args);

/// Largest invoke arguments sent in a frame: the gateway's WebSocket frames
/// are at most 64 KiB (ADR 0011).
const int maxFrameArgs = 60 * 1024;

class FrameClient implements WyrmApi {
  final FrameTransport _t;
  final BulkInvoke? _bulk;
  final Map<int, _Pending> _pending = {};
  late final StreamSubscription<Value> _sub;
  int _nextId = 1; // id 0 is the server's "unparsable frame"
  bool _closed = false;

  /// [bulk] carries invokes whose arguments do not fit a frame (the
  /// gateway's `POST /api/invoke`); without it they go in a frame anyway.
  FrameClient(this._t, {BulkInvoke? bulk}) : _bulk = bulk {
    _sub = _t.incoming.listen(_onFrame, onDone: _onGone, onError: (Object _) => _onGone());
  }

  bool get isClosed => _closed;

  int _id() => _nextId++;

  void _send(int id, String op, String key, {Value? value, String? action, Value? args, int? sub}) {
    if (_closed) throw WyrmException.of(Status.disconnected, 'client closed');
    _t.send({
      'id': VInt(id),
      'op': VStr(op),
      if (key.isNotEmpty) 'key': VStr(key),
      if (value != null) 'value': value,
      if (action != null) 'action': VStr(action),
      if (args != null) 'args': args,
      if (sub != null) 'sub': VInt(sub),
    });
  }

  void _onFrame(Value f) {
    final id = switch (f['id']) { VInt(:final v) => v, _ => null };
    if (id == null) return;
    final p = _pending[id];
    if (p == null) return; // a cancelled stream, or id 0
    final ev = f['event'];
    if (ev is VMap) {
      final type = switch (ev['type']) { VStr(:final v) => v, _ => '' };
      if (type == 'closed') {
        _pending.remove(id);
        p.done();
      } else {
        p.event(type, ev);
      }
      return;
    }
    if (f['ok'] == const VBool(true)) {
      if (!p.isStream) _pending.remove(id);
      p.ok(f['result']);
    } else {
      _pending.remove(id);
      p.fail(_error(f['error']));
    }
  }

  static WyrmException _error(Value? e) {
    final status = switch (e?['status']) { VInt(:final v) => v, _ => Status.internalError.code };
    final msg = switch (e?['message']) { VStr(:final v) => v, _ => 'error' };
    return WyrmException(StatusCode(status), msg);
  }

  void _onGone() {
    _closed = true;
    final all = _pending.values.toList();
    _pending.clear();
    for (final p in all) {
      p.fail(WyrmException.of(Status.disconnected, 'connection closed'));
    }
  }

  Future<Value?> _oneShot(String op, String key, {Value? value, String? action, Value? args}) {
    final c = Completer<Value?>();
    final id = _id();
    _pending[id] = _Pending.oneShot(c);
    try {
      _send(id, op, key, value: value, action: action, args: args);
    } catch (e) {
      _pending.remove(id);
      return Future.error(e);
    }
    return c.future;
  }

  /// A server stream (`list` / `subscribe`): request on listen, `unsubscribe`
  /// on cancel.
  Stream<T> _stream<T>(String op, String key, T? Function(String type, VMap ev) map) {
    late StreamController<T> ctl;
    int? id;
    ctl = StreamController<T>(
      onListen: () {
        final i = _id();
        id = i;
        _pending[i] = _Pending.stream(
          onEvent: (type, ev) {
            try {
              final x = map(type, ev);
              if (x != null) ctl.add(x);
            } catch (e, st) {
              ctl.addError(e, st);
            }
          },
          onFail: (e) {
            ctl.addError(e);
            ctl.close();
          },
          onDone: () => ctl.close(),
        );
        try {
          _send(i, op, key);
        } catch (e) {
          _pending.remove(i);
          ctl.addError(e);
          ctl.close();
        }
      },
      onCancel: () {
        final i = id;
        if (i != null && _pending.remove(i) != null && !_closed) {
          final u = _id();
          _pending[u] = _Pending.oneShot(Completer<Value?>()..future.ignore());
          _send(u, 'unsubscribe', '', sub: i);
        }
      },
    );
    return ctl.stream;
  }

  @override
  Stream<ListUpdate> list(String key) => _stream('list', key, (type, ev) {
        String name() => switch (ev['name']) { VStr(:final v) => v, _ => throw _bad('name') };
        return switch (type) {
          'refreshed' => ListRefreshed(switch (ev['children']) {
              VArray(:final v) => [for (final c in v) _child(c)],
              _ => throw _bad('children'),
            }),
          'added' => ChildAdded(_child(ev)),
          'changed' => ChildChanged(_child(ev)),
          'removed' => ChildRemoved(name()),
          'connected' => ChildConnected(name()),
          'disconnected' => ChildDisconnected(switch (ev['name']) { VStr(:final v) => v, _ => null }),
          _ => null, // unknown event: forward compatible
        };
      });

  @override
  Stream<ValEvent> subscribe(String pattern) => _stream('subscribe', pattern, (type, ev) {
        final key = switch (ev['key']) { VStr(:final v) => v, _ => throw _bad('key') };
        switch (type) {
          case 'sample':
            final q = switch (ev['q']) {
              VStr(:final v) => Quality.fromName(v) ?? Quality.bad,
              VInt(:final v) => Quality.fromCode(v) ?? Quality.bad,
              _ => Quality.good,
            };
            final t = switch (ev['t']) { VInt(:final v) => v, _ => 0 };
            final qual = switch (ev['qual']) { VStr(:final v) => v, _ => null };
            return ValSample(key, Sample(ev['v'] ?? const VNull(), q: q, t: t), qual: qual);
          case 'removed':
            return ValRemoved(key);
        }
        return null;
      });

  @override
  Future<void> set(String key, Value value) => _oneShot('set', key, value: value);

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) {
    final a = args ?? const VMap({});
    final bulk = _bulk;
    if (bulk != null && a.toCbor().length > maxFrameArgs) {
      return Stream.fromFuture(bulk(key, action, a)).where((v) => v is! VNull);
    }
    late StreamController<Value> ctl;
    ctl = StreamController<Value>(onListen: () {
      final id = _id();
      _pending[id] = _Pending.invoke(
        onValue: (v) => ctl.add(v),
        onOk: (last) {
          if (last != null) ctl.add(last);
          ctl.close();
        },
        onFail: (e) {
          ctl.addError(e);
          ctl.close();
        },
      );
      try {
        _send(id, 'invoke', key, action: action, args: a);
      } catch (e) {
        _pending.remove(id);
        ctl.addError(e);
        ctl.close();
      }
    });
    return ctl.stream;
  }

  @override
  Future<NodeMeta> meta(String key) async {
    final r = await _oneShot('meta', key);
    if (r is! VBytes) throw _bad('meta');
    return NodeMeta.fromCbor(r.v);
  }

  @override
  Future<List<Child>> children(String key) async {
    final r = await _oneShot('children', key);
    if (r is! VArray) throw _bad('children');
    return [for (final c in r.v) _child(c)];
  }

  @override
  Future<List<HistRow>> history(String key,
      {required String from, String to = '', String? agg, String? window, int? limit}) async {
    final args = <String, Value>{
      'from': VStr(from),
      if (to.isNotEmpty) 'to': VStr(to),
      if (agg != null && agg.isNotEmpty) 'agg': VStr(agg),
      if (window != null && window.isNotEmpty) 'window': VStr(window),
      if (limit != null) 'limit': VInt(limit),
    };
    final r = await _oneShot('history', key, args: VMap(args));
    if (r is! VArray) throw _bad('history');
    return [for (final row in r.v) _histRow(row)];
  }

  static HistRow _histRow(Value row) {
    if (row is! VArray || row.v.length < 2 || row.v.length > 3) throw _bad('history row');
    final t = switch (row.v[0]) { VInt(:final v) => v, _ => throw _bad('history time') };
    final q = row.v.length == 3
        ? switch (row.v[2]) { VInt(:final v) => Quality.fromCode(v), _ => null }
        : null;
    return HistRow(t, row.v[1], q);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _onGone();
    await _t.close();
    await _sub.cancel();
  }

  static Child _child(Value c) {
    final name = switch (c['name']) { VStr(:final v) => v, _ => throw _bad('child name') };
    final meta = switch (c['meta']) {
      VBytes(:final v) => NodeMeta.fromCbor(v),
      _ => throw _bad('child meta'),
    };
    return Child(name, meta);
  }

  static WyrmException _bad(String what) =>
      WyrmException.of(Status.invalidMessage, 'malformed frame: $what');
}

class _Pending {
  final bool isStream;
  final void Function(String type, VMap ev) event;
  final void Function(Value? result) ok;
  final void Function(WyrmException e) fail;
  final void Function() done;

  _Pending._(this.isStream, this.event, this.ok, this.fail, this.done);

  factory _Pending.oneShot(Completer<Value?> c) => _Pending._(
        false,
        (_, _) {},
        (r) => c.isCompleted ? null : c.complete(r),
        (e) => c.isCompleted ? null : c.completeError(e),
        () => c.isCompleted ? null : c.complete(null),
      );

  factory _Pending.stream({
    required void Function(String, VMap) onEvent,
    required void Function(WyrmException) onFail,
    required void Function() onDone,
  }) =>
      _Pending._(true, onEvent, (_) {}, onFail, onDone);

  factory _Pending.invoke({
    required void Function(Value) onValue,
    required void Function(Value?) onOk,
    required void Function(WyrmException) onFail,
  }) =>
      _Pending._(
        false,
        (type, ev) {
          if (type == 'value') onValue(ev['v'] ?? const VNull());
        },
        onOk,
        onFail,
        () => onOk(null),
      );
}

/// CBOR helpers for transports.
Uint8List encodeFrame(Map<String, Value> frame) => VMap(frame).toCbor();
Value decodeFrame(List<int> bytes) => Value.fromCbor(bytes);
