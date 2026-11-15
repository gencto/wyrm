// The client API that every transport implements (gateway, FFI, fakes).

import 'dart:typed_data';

import 'package:wyrm_core/wyrm_core.dart';

import 'gateway_types.dart';

/// A failed request: a spec-04 status and a message.
class WyrmException implements Exception {
  final StatusCode status;
  final String message;

  /// The refusal code a gateway gives (ADR 0050) as text, also one this
  /// client does not know; `null` for any other error. [refusal] is the
  /// typed form.
  final String? code;

  /// The refusal as a [GatewayRefusal]; null for an error without a code
  /// and for a code this client does not know (see [code]).
  GatewayRefusal? get refusal {
    final c = code;
    return c == null ? null : GatewayRefusal.fromWire(c);
  }

  /// What a `confirm_required` refusal carries to sign: `nonce` (absent for
  /// a session that cannot confirm) and `request` (the request's hash).
  final Uint8List? nonce;
  final Uint8List? request;

  WyrmException(
    this.status,
    this.message, {
    this.code,
    this.nonce,
    this.request,
  });
  WyrmException.of(
    Status s,
    this.message, {
    this.code,
    this.nonce,
    this.request,
  }) : status = StatusCode.of(s);

  /// The exception an error map `{status, message, code?, nonce?, request?}`
  /// stands for.
  factory WyrmException.fromError(Value? e, {String fallback = 'error'}) =>
      WyrmException(
        StatusCode(switch (e?['status']) {
          VInt(:final v) => v,
          _ => Status.internalError.code,
        }),
        switch (e?['message']) {
          VStr(:final v) => v,
          _ => fallback,
        },
        code: switch (e?['code']) {
          VStr(:final v) => v,
          _ => null,
        },
        nonce: switch (e?['nonce']) {
          VBytes(:final v) => v,
          _ => null,
        },
        request: switch (e?['request']) {
          VBytes(:final v) => v,
          _ => null,
        },
      );

  /// A reply that does not have the shape its decoder reads.
  WyrmException.malformed(DecodeError e)
    : status = StatusCode.of(Status.invalidMessage),
      message = 'malformed reply: ${e.path}: expected ${e.expected}, got ${e.got}',
      code = null,
      nonce = null,
      request = null;

  @override
  String toString() => 'WyrmException(${status.name}): $message';
}

/// [decode] of [v]; a [DecodeError] becomes a [WyrmException] with status
/// `invalid_message` that names the field, so a caller handles one error
/// type for every call.
T decodeReply<T>(Value v, T Function(Value v) decode) {
  try {
    return decode(v);
  } on DecodeError catch (e) {
    throw WyrmException.malformed(e);
  }
}

/// One child of a node: its name and its `view=list` meta.
class Child {
  final String name;
  final NodeMeta meta;
  const Child(this.name, this.meta);

  @override
  String toString() => 'Child($name)';
}

/// An event of a reactive `list`.
sealed class ListUpdate {
  const ListUpdate();
}

/// Full snapshot: the first event, and again after the owner reconnects.
final class ListRefreshed extends ListUpdate {
  final List<Child> children;
  const ListRefreshed(this.children);
}

final class ChildAdded extends ListUpdate {
  final Child child;
  const ChildAdded(this.child);
}

final class ChildChanged extends ListUpdate {
  final Child child;
  const ChildChanged(this.child);
}

final class ChildRemoved extends ListUpdate {
  final String name;
  const ChildRemoved(this.name);
}

/// A dynamic child is back.
final class ChildConnected extends ListUpdate {
  final String name;
  const ChildConnected(this.name);
}

/// `name == null`: the owning link is gone; else a dynamic child is gone.
final class ChildDisconnected extends ListUpdate {
  final String? name;
  const ChildDisconnected(this.name);
}

/// An event of `subscribe`.
sealed class ValEvent {
  /// Node key (without `/~val`).
  String get key;
  const ValEvent();
}

final class ValSample extends ValEvent {
  @override
  final String key;
  final Sample sample;

  /// Extended quality (`bad/comm_fail`, …), if any.
  final String? qual;
  const ValSample(this.key, this.sample, {this.qual});

  @override
  String toString() =>
      'ValSample($key, $sample${qual == null ? '' : ', $qual'})';
}

final class ValRemoved extends ValEvent {
  @override
  final String key;
  const ValRemoved(this.key);
}

/// Requester operations on the node tree. Keys are full node keys
/// (`wy/<site>/…`) without a `~` suffix.
///
/// Streams start their request when listened to and end it on cancel.
abstract interface class WyrmApi {
  /// Reactive children of [key]: [ListRefreshed] first, then changes.
  Stream<ListUpdate> list(String key);

  /// Values of a node or a pattern (`…/mock/**`): stored values first,
  /// then live samples.
  Stream<ValEvent> subscribe(String pattern);

  /// Write [value] to `key/~set`.
  Future<void> set(String key, Value value);

  /// Invoke [action] on [key]: every result in order (one for a plain
  /// action, many for a stream action).
  Stream<Value> invoke(String key, String action, [Value? args]);

  Future<NodeMeta> meta(String key);

  /// One-shot children of [key].
  Future<List<Child>> children(String key);

  /// Recorded values of the point [key] (spec 01 `~val?history=`), in time
  /// order: `[t, v, q]` rows, or with [agg] or [window] `[t_start, v]` rows
  /// (`q` null). [from] and [to] are RFC 3339 (`to` empty: now). Empty when
  /// nobody records the point (a watch in `sys/history` does).
  Future<List<HistRow>> history(
    String key, {
    required String from,
    String to = '',
    String? agg,
    String? window,
    int? limit,
  });

  /// A document of the node [key]: [suffix] is `~state` or `~def` (spec 01).
  /// Rights as `list` on the node; a restricted node (an agent's `tasks`)
  /// decides by the caller's own rights. A gateway older than the op answers
  /// `invalid_parameter` ([isUnknownOp]).
  Future<Value> doc(String key, String suffix);

  /// End every stream and the connection.
  Future<void> close();
}

/// Typed forms of [WyrmApi] calls that take a closed set as text.
extension TypedCalls on WyrmApi {
  /// [WyrmApi.history] with [agg] as a [HistoryAgg]. [window] is
  /// `<n>s|m|h|d|w` (`5m`, `1h`).
  Future<List<HistRow>> historyOf(
    String key, {
    required String from,
    String to = '',
    HistoryAgg? agg,
    String? window,
    int? limit,
  }) => history(
    key,
    from: from,
    to: to,
    agg: agg?.wire,
    window: window,
    limit: limit,
  );

  /// [WyrmApi.doc] with [suffix] as a [DocSuffix].
  Future<Value> docOf(String key, DocSuffix suffix) => doc(key, suffix.wire);
}

/// Is [e] the answer of a gateway that does not know the op (one older than
/// `doc`)?
bool isUnknownOp(WyrmException e) =>
    e.status.known == Status.invalidParameter &&
    e.message.startsWith('unknown op');
