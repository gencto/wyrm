// The client API that every transport implements (gateway, FFI, fakes).

import 'package:wyrm_core/wyrm_core.dart';

/// A failed request: a spec-04 status and a message.
class WyrmException implements Exception {
  final StatusCode status;
  final String message;
  WyrmException(this.status, this.message);
  WyrmException.of(Status s, this.message) : status = StatusCode.of(s);

  @override
  String toString() => 'WyrmException(${status.name}): $message';
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
  String toString() => 'ValSample($key, $sample${qual == null ? '' : ', $qual'})';
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

  /// End every stream and the connection.
  Future<void> close();
}
