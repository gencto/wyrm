import 'dart:async';

import 'package:models/live_value.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/mappers/live_value_mapper.dart';

/// What [LiveValuesService] tells its listener.
abstract class LiveValuesServiceListener {
  /// The keys whose value changed since the last call, at most every
  /// [LiveValuesService.flushEvery] (ADR 0037 rule 5). A null value is a
  /// removed key.
  void onValues(Map<String, LiveValue?> changed);

  /// The subscription of [key] failed with [error]; it is closed. When the
  /// broker could not be reached it is opened again every
  /// [LiveValuesService.retryEvery] while the key is watched.
  void onError(String key, Object error);
}

/// One `subscribe` per watched key or pattern, opened and closed as the set
/// changes ([sync]); samples are buffered and handed over in batches.
class LiveValuesService extends DisposableServiceInterface {
  LiveValuesService({
    required this._listener,
    this.flushEvery = const Duration(milliseconds: 200),
    this.retryEvery = const Duration(seconds: 5),
  });

  final LiveValuesServiceListener _listener;

  /// How often the buffer is handed to the listener.
  final Duration flushEvery;

  /// How long a subscription that lost its broker waits before it is opened
  /// again.
  final Duration retryEvery;
  final _want = <String>{};
  final _retries = <String, Timer>{};

  WyrmApi? _api;
  final _subs = <String, StreamSubscription<ValEvent>>{};
  final _pending = <String, LiveValue?>{};
  Timer? _timer;

  /// The keys and patterns subscribed now.
  Set<String> get watched => _subs.keys.toSet();

  /// Uses [api] for the subscriptions and opens the ones in [watched].
  void attach(WyrmApi api, Iterable<String> watched) {
    _closeAll();
    _api = api;
    sync(watched);
  }

  /// Opens a subscription for each key of [watched] not open yet and closes
  /// the ones no longer in it.
  void sync(Iterable<String> watched) {
    final want = watched.toSet();
    _want
      ..clear()
      ..addAll(want);
    for (final k in _subs.keys.toList()) {
      if (!want.contains(k)) {
        unawaited(_subs.remove(k)!.cancel());
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
      if (!_subs.containsKey(k) && !_retries.containsKey(k)) {
        _open(k);
      }
    }
  }

  /// Opens the subscription of [k] again now, when it is watched and not
  /// open (*Try again* on a `read failed` mark): one that failed on a
  /// refusal is not opened again by itself.
  void retry(String k) {
    _retries.remove(k)?.cancel();
    if (_want.contains(k) && !_subs.containsKey(k)) {
      _open(k);
    }
  }

  void _open(String k) {
    final api = _api;
    if (api == null) {
      return;
    }
    _subs[k] = api
        .subscribe(k)
        .listen(
          _onEvent,
          // A failed subscription ends just that key; the others keep
          // running. The listener hears why (the row's `read failed` mark,
          // a line in Problems).
          onError: (Object e) {
            logger.fine('subscribe $k: $e');
            unawaited(_subs.remove(k)?.cancel());
            _listener.onError(k, e);
            if (_lost(e)) {
              _retries[k] = Timer(retryEvery, () {
                _retries.remove(k);
                if (_want.contains(k) && !_subs.containsKey(k)) {
                  _open(k);
                }
              });
            }
          },
        );
  }

  /// The broker could not be reached (it may be back later); a refusal on
  /// rights or a missing key is final until the key is watched again.
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

  void _onEvent(ValEvent e) {
    switch (e) {
      case ValSample(:final key, :final sample):
        _pending[key] = liveValueOf(sample);
      case ValRemoved(:final key):
        _pending[key] = null;
    }
    _timer ??= Timer(flushEvery, flush);
  }

  /// Hands the buffer to the listener now.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final batch = Map.of(_pending);
    _pending.clear();
    _listener.onValues(batch);
  }

  void _closeAll() {
    for (final s in _subs.values) {
      unawaited(s.cancel());
    }
    _subs.clear();
    for (final t in _retries.values) {
      t.cancel();
    }
    _retries.clear();
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  /// Closes every subscription and forgets the session.
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
