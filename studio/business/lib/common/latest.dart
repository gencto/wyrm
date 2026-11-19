import 'dart:async';

import 'package:equatable/equatable.dart';

/// The reads that may be started again before they answered.
enum LatestRead {
  /// The links of a site (`sys/links`).
  links,

  /// A flow opened in the editor: one order for every flow of a site.
  flowOpen,

  /// The flow on screen read again after a redeploy.
  flowReread,
}

/// What one order of requests is about: a kind of read and its target (a
/// site's root, a flow's key). Two targets never share an order, so a read
/// of one site says nothing of another's.
final class LatestKey extends Equatable {
  const LatestKey(this.read, this.target);

  final LatestRead read;

  /// The site's root, or the full key of what is read.
  final String target;

  @override
  List<Object?> get props => [read, target];
}

/// One request of a [LatestKey]: its place in the order, and how it ended
/// for whoever waits for a request it replaced.
final class LatestRun {
  LatestRun._(this._owner, this.key, this.token);

  final Latest _owner;
  final LatestKey key;

  /// Its place among the requests of the store: a later one is higher.
  final int token;

  final _done = Completer<void>();

  /// A request of the same key was started after this one.
  bool get replaced => _owner.started(key) > token;

  /// The answer of a request started after this one was kept already:
  /// this one is older than what the state holds.
  bool get outdated => (_owner._kept[key] ?? 0) > token;

  /// Its answer is the one the state holds now.
  void keep() {
    if (token > (_owner._kept[key] ?? 0)) {
      _owner._kept[key] = token;
    }
  }

  /// It ended; with [error] when it failed. Whoever waits for it
  /// ([Latest.newer]) ends the same way.
  void end([Object? error, StackTrace? stack]) {
    if (_done.isCompleted) {
      return;
    }
    if (error == null) {
      _done.complete();
    } else {
      // nobody may be waiting: the failure is then the run's own to say
      _done.future.ignore();
      _done.completeError(error, stack);
    }
  }
}

/// The order of the requests of one store, by [LatestKey]: which was
/// started last and which answer was kept last. A read that anybody may
/// start again before it answered (a site switch, a second flow opened)
/// takes its place when it starts and asks, after its `await`s, whether its
/// answer is still the one to keep. Nothing waits to start here: a newer
/// request goes out at once, and the older one's answer is dropped when it
/// comes.
///
/// One per store (`AppDependencies.latest`), so two stores never share an
/// order.
final class Latest {
  var _count = 0;
  final _started = <LatestKey, LatestRun>{};
  final _kept = <LatestKey, int>{};

  /// A request of [key] starts: the newest of the store.
  LatestRun start(LatestKey key) =>
      _started[key] = LatestRun._(this, key, ++_count);

  /// The place of the request of [key] started last; 0 before the first.
  int started(LatestKey key) => _started[key]?.token ?? 0;

  /// How the request that replaced [run] ends: completes when it ended
  /// well, fails as it failed. Null when nothing replaced [run]. A request
  /// that was replaced and failed has nothing fresh for whoever awaits it;
  /// the newer one's outcome is theirs.
  Future<void>? newer(LatestRun run) => switch (_started[run.key]) {
    final last? when last.token > run.token => last._done.future,
    _ => null,
  };
}
