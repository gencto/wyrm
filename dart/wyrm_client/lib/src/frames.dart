// The frame protocol of the gateway WebSocket (crates/wyrm-gateway/src/ws.rs),
// shared by every transport:
//
// client → server: `{id, op, key, value?, action?, args?, sub?, suffix?}`
// server → client: `{id, ok: true, result?}` | `{id, ok: false, error: {status, message}}`
//                  `{id, event: {type, …}}`
//
// Both directions are typed here: a transport gets a [FrameRequest] and
// gives [Value] frames, which [ServerFrame.fromValue] reads once.

import 'dart:async';
import 'dart:typed_data';

import 'package:wyrm_core/wyrm_core.dart';

import 'api.dart';

/// The `op` of a request frame (`ws.rs` `Req.op`). Closed: the gateway
/// answers another op with `invalid_parameter` ([isUnknownOp]).
enum FrameOp implements WireName {
  list('list'),
  subscribe('subscribe'),
  unsubscribe('unsubscribe'),
  set('set'),
  invoke('invoke'),
  meta('meta'),
  children('children'),
  history('history'),
  doc('doc'),

  /// Check a call without running it (spec 05 0.2.33).
  check('check');

  @override
  final String wire;
  const FrameOp(this.wire);

  static FrameOp? fromWire(String s) => wireByName(values, s);
}

/// The `type` of an event frame (`ws.rs` `event_frame`). The set may grow:
/// an event of a type this client does not know is skipped.
enum FrameEventKind implements WireName {
  /// `list`: the full snapshot.
  refreshed('refreshed'),
  added('added'),
  changed('changed'),

  /// `list`: a child is gone; `subscribe`: a point is gone.
  removed('removed'),
  connected('connected'),
  disconnected('disconnected'),

  /// `subscribe`: a value.
  sample('sample'),

  /// `invoke`: one result of a stream action.
  value('value'),

  /// The stream ended.
  closed('closed');

  @override
  final String wire;
  const FrameEventKind(this.wire);

  static FrameEventKind? fromWire(String s) => wireByName(values, s);
}

/// One request frame.
final class FrameRequest {
  final int id;
  final FrameOp op;

  /// The node key; empty for `unsubscribe`.
  final String key;
  final Value? value;
  final String? action;
  final Value? args;

  /// `unsubscribe`: the id of the stream to end.
  final int? sub;

  /// `doc`: which document.
  final DocSuffix? suffix;

  const FrameRequest(
    this.id,
    this.op,
    this.key, {
    this.value,
    this.action,
    this.args,
    this.sub,
    this.suffix,
  });

  /// The frame as the gateway reads it.
  VMap toValue() => VMap({
    'id': VInt(id),
    'op': VStr(op.wire),
    if (key.isNotEmpty) 'key': VStr(key),
    'value': ?value,
    'action': ?(action == null ? null : VStr(action!)),
    'args': ?args,
    'sub': ?(sub == null ? null : VInt(sub!)),
    'suffix': ?(suffix == null ? null : VStr(suffix!.wire)),
  });

  @override
  String toString() => 'FrameRequest($id, ${op.wire}, $key)';
}

/// One frame from the server.
sealed class ServerFrame {
  /// The request it answers; 0 for an unparsable request.
  final int id;
  const ServerFrame(this.id);

  /// Reads [v]; a frame without an `id` is a [DecodeError]. An event of an
  /// unknown type gives [FrameIgnored].
  static ServerFrame fromValue(Value v) {
    final m = WireMap.of(v, 'ServerFrame');
    final id = m.integer('id');
    if (m.has('event')) {
      final ev = m.map('event');
      final kind = FrameEventKind.fromWire(ev.str('type'));
      return kind == null ? FrameIgnored(id) : FrameEvent(id, kind, ev);
    }
    if (m.boolean('ok')) return FrameOk(id, m['result']);
    return FrameFailed(id, WyrmException.fromError(m['error']));
  }
}

/// `{id, ok: true, result?}`.
final class FrameOk extends ServerFrame {
  final Value? result;
  const FrameOk(super.id, this.result);
}

/// `{id, ok: false, error}`.
final class FrameFailed extends ServerFrame {
  final WyrmException error;
  const FrameFailed(super.id, this.error);
}

/// `{id, event: {type, …}}`; [fields] are the event's fields.
final class FrameEvent extends ServerFrame {
  final FrameEventKind kind;
  final WireMap fields;
  const FrameEvent(super.id, this.kind, this.fields);
}

/// An event this client does not know.
final class FrameIgnored extends ServerFrame {
  const FrameIgnored(super.id);
}

/// Carries frames. [send] takes the typed request; the transport encodes
/// it (CBOR over a WebSocket, or a call into the FFI library).
abstract interface class FrameTransport {
  /// Decoded server frames. Done = the connection is gone.
  Stream<Value> get incoming;

  void send(FrameRequest frame);

  Future<void> close();
}

/// One invoke outside the frame transport: `(key, action, args)` → the last
/// result. For arguments larger than a frame ([maxFrameArgs]).
typedef BulkInvoke =
    Future<Value> Function(String key, String action, Value args);

/// Largest invoke arguments sent in a frame: the gateway's WebSocket frames
/// are at most 64 KiB (ADR 0011).
const int maxFrameArgs = 60 * 1024;

/// [WyrmApi] over a [FrameTransport].
class FrameClient implements WyrmApi {
  final FrameTransport _t;
  final BulkInvoke? _bulk;
  final Map<int, _Pending> _pending = {};
  late final StreamSubscription<Value> _sub;
  int _nextId = 1; // id 0 is the server's "unparsable frame"
  bool _closed = false;

  /// [_bulk] carries invokes whose arguments do not fit a frame (the
  /// gateway's `POST /api/invoke`); without it they go in a frame anyway.
  FrameClient(this._t, {this._bulk}) {
    _sub = _t.incoming.listen(
      _onFrame,
      onDone: _onGone,
      onError: (Object _) => _onGone(),
    );
  }

  bool get isClosed => _closed;

  /// Completes when the connection is gone (closed here or by the server).
  Future<void> get done => _done.future;
  final _done = Completer<void>();

  int _id() => _nextId++;

  void _send(FrameRequest r) {
    if (_closed) throw WyrmException.of(Status.disconnected, 'client closed');
    _t.send(r);
  }

  void _onFrame(Value v) {
    final ServerFrame f;
    try {
      f = ServerFrame.fromValue(v);
    } on DecodeError {
      return; // a frame without an id belongs to no request
    }
    final p = _pending[f.id];
    if (p == null) return; // a cancelled stream, or id 0
    switch (f) {
      case FrameIgnored():
        return;
      case FrameEvent(kind: FrameEventKind.closed):
        _pending.remove(f.id);
        p.done();
      case FrameEvent(:final kind, :final fields):
        p.event(kind, fields);
      case FrameOk(:final result):
        if (!p.isStream) _pending.remove(f.id);
        p.ok(result);
      case FrameFailed(:final error):
        _pending.remove(f.id);
        p.fail(error);
    }
  }

  void _onGone() {
    _closed = true;
    if (!_done.isCompleted) _done.complete();
    final all = _pending.values.toList();
    _pending.clear();
    for (final p in all) {
      p.fail(WyrmException.of(Status.disconnected, 'connection closed'));
    }
  }

  Future<Value?> _oneShot(
    FrameOp op,
    String key, {
    Value? value,
    String? action,
    Value? args,
    DocSuffix? suffix,
  }) {
    final c = Completer<Value?>();
    final id = _id();
    _pending[id] = _Pending.oneShot(c);
    try {
      _send(
        FrameRequest(
          id,
          op,
          key,
          value: value,
          action: action,
          args: args,
          suffix: suffix,
        ),
      );
    } catch (e) {
      _pending.remove(id);
      return Future.error(e);
    }
    return c.future;
  }

  /// A server stream (`list` / `subscribe`): request on listen, `unsubscribe`
  /// on cancel.
  Stream<T> _stream<T>(
    FrameOp op,
    String key,
    T? Function(FrameEventKind kind, WireMap ev) map,
  ) {
    late StreamController<T> ctl;
    int? id;
    ctl = StreamController<T>(
      onListen: () {
        final i = _id();
        id = i;
        _pending[i] = _Pending.stream(
          onEvent: (kind, ev) {
            try {
              final x = map(kind, ev);
              if (x != null) ctl.add(x);
            } on DecodeError catch (e, st) {
              ctl.addError(WyrmException.malformed(e), st);
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
          _send(FrameRequest(i, op, key));
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
          _send(FrameRequest(u, FrameOp.unsubscribe, '', sub: i));
        }
      },
    );
    return ctl.stream;
  }

  @override
  Stream<ListUpdate> list(String key) =>
      _stream(FrameOp.list, key, (kind, ev) => switch (kind) {
        FrameEventKind.refreshed => ListRefreshed(
          ev.list('children', (c, path) => _child(WireMap.of(c, path))),
        ),
        FrameEventKind.added => ChildAdded(_child(ev)),
        FrameEventKind.changed => ChildChanged(_child(ev)),
        FrameEventKind.removed => ChildRemoved(ev.str('name')),
        FrameEventKind.connected => ChildConnected(ev.str('name')),
        FrameEventKind.disconnected => ChildDisconnected(ev.strOrNull('name')),
        // not a list event: forward compatible
        FrameEventKind.sample ||
        FrameEventKind.value ||
        FrameEventKind.closed => null,
      });

  @override
  Stream<ValEvent> subscribe(String pattern) =>
      _stream(FrameOp.subscribe, pattern, (kind, ev) => switch (kind) {
        FrameEventKind.sample => ValSample(
          ev.str('key'),
          Sample(
            ev['v'] ?? const VNull(),
            q:
                ev.codeOrNameOrNull('q', Quality.values) ?? Quality.good,
            t: ev.integerOr('t', 0),
          ),
          qual: ev.strOrNull('qual'),
        ),
        FrameEventKind.removed => ValRemoved(ev.str('key')),
        FrameEventKind.refreshed ||
        FrameEventKind.added ||
        FrameEventKind.changed ||
        FrameEventKind.connected ||
        FrameEventKind.disconnected ||
        FrameEventKind.value ||
        FrameEventKind.closed => null,
      });

  @override
  Future<void> set(String key, Value value) =>
      _oneShot(FrameOp.set, key, value: value);

  @override
  Stream<Value> invoke(String key, String action, [Value? args]) {
    final a = args ?? const VMap({});
    final bulk = _bulk;
    if (bulk != null && a.toCbor().length > maxFrameArgs) {
      return Stream.fromFuture(bulk(key, action, a)).where((v) => v is! VNull);
    }
    late StreamController<Value> ctl;
    ctl = StreamController<Value>(
      onListen: () {
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
          _send(FrameRequest(id, FrameOp.invoke, key, action: action, args: a));
        } catch (e) {
          _pending.remove(id);
          ctl.addError(e);
          ctl.close();
        }
      },
    );
    return ctl.stream;
  }

  @override
  Future<NodeMeta> meta(String key) async {
    final r = await _oneShot(FrameOp.meta, key);
    if (r is! VBytes) throw _bad('meta', r);
    return NodeMeta.fromCbor(r.v);
  }

  @override
  Future<List<Child>> children(String key) async {
    final r = await _oneShot(FrameOp.children, key);
    if (r is! VArray) throw _bad('children', r);
    return decodeReply<List<Child>>(
      r,
      (_) => [
        for (final (i, c) in r.v.indexed)
          _child(WireMap.of(c, 'children[$i]')),
      ],
    );
  }

  @override
  Future<List<HistRow>> history(
    String key, {
    required String from,
    String to = '',
    String? agg,
    String? window,
    int? limit,
  }) async {
    final args = <String, Value>{
      'from': VStr(from),
      if (to.isNotEmpty) 'to': VStr(to),
      if (agg != null && agg.isNotEmpty) 'agg': VStr(agg),
      if (window != null && window.isNotEmpty) 'window': VStr(window),
      'limit': ?(limit == null ? null : VInt(limit)),
    };
    final r = await _oneShot(FrameOp.history, key, args: VMap(args));
    if (r is! VArray) throw _bad('history', r);
    return [for (final (i, row) in r.v.indexed) _histRow(row, i)];
  }

  @override
  Future<Value> doc(String key, String suffix) async {
    final s = DocSuffix.fromWire(suffix);
    if (s == null) {
      throw WyrmException.of(
        Status.invalidParameter,
        'suffix: ~state or ~def required',
      );
    }
    return await _oneShot(FrameOp.doc, key, suffix: s) ?? const VNull();
  }

  static HistRow _histRow(Value row, int i) {
    if (row is! VArray || row.v.length < 2 || row.v.length > 3) {
      throw _bad('history[$i]', row);
    }
    final t = switch (row.v[0]) {
      VInt(:final v) => v,
      final other => throw _bad('history[$i][0]', other),
    };
    final q = row.v.length == 3
        ? switch (row.v[2]) {
            VInt(:final v) => Quality.fromCode(v),
            _ => null,
          }
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

  /// A child `{name, meta}` (meta: the `view=list` summary as CBOR bytes).
  static Child _child(WireMap c) {
    final name = c.str('name');
    try {
      return Child(name, NodeMeta.fromCbor(c.bytes('meta')));
    } on CborError catch (e) {
      throw DecodeError('${c.path}.meta', 'a view=list summary', '$e');
    }
  }

  static WyrmException _bad(String what, Value? got) => WyrmException.malformed(
    DecodeError.of('frame.$what', 'its shape', got),
  );
}

class _Pending {
  final bool isStream;
  final void Function(FrameEventKind kind, WireMap ev) event;
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
    required void Function(FrameEventKind, WireMap) onEvent,
    required void Function(WyrmException) onFail,
    required void Function() onDone,
  }) => _Pending._(true, onEvent, (_) {}, onFail, onDone);

  factory _Pending.invoke({
    required void Function(Value) onValue,
    required void Function(Value?) onOk,
    required void Function(WyrmException) onFail,
  }) => _Pending._(
    false,
    (kind, ev) {
      if (kind == FrameEventKind.value) onValue(ev['v'] ?? const VNull());
    },
    onOk,
    onFail,
    () => onOk(null),
  );
}

/// CBOR helpers for transports.
Uint8List encodeFrame(FrameRequest frame) => frame.toValue().toCbor();
Value decodeFrame(List<int> bytes) => Value.fromCbor(bytes);
