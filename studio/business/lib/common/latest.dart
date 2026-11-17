/// The order of the requests of one store, by key: which was started last
/// and which answer was kept last. A read that anybody may start again
/// before it answered (a site switch, a second flow opened) takes a token
/// when it starts and asks here, after its `await`s, whether its answer is
/// still the one to keep. Nothing waits here: a newer request goes out at
/// once, and the older one's answer is dropped when it comes.
///
/// One per store (`AppDependencies.latest`), so two stores never share an
/// order.
final class Latest {
  var _count = 0;
  final _started = <Object, int>{};
  final _kept = <Object, int>{};

  /// A request of [key] starts: its token, the newest of the store.
  int start(Object key) => _started[key] = ++_count;

  /// The token of the request of [key] started last; 0 before the first.
  int started(Object key) => _started[key] ?? 0;

  /// A request of [key] was started after the one that holds [token].
  bool newerStarted(Object key, int token) => started(key) > token;

  /// The answer of a request of [key] started after the one that holds
  /// [token] was kept already: this one is older than what the state holds.
  bool newerKept(Object key, int token) => (_kept[key] ?? 0) > token;

  /// The answer of the request of [key] that holds [token] is kept.
  void keep(Object key, int token) {
    if (token > (_kept[key] ?? 0)) {
      _kept[key] = token;
    }
  }
}
