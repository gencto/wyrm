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
}

/// One `subscribe` per watched key or pattern, opened and closed as the set
/// changes ([sync]); samples are buffered and handed over in batches.
class LiveValuesService extends DisposableServiceInterface {
  LiveValuesService({
    required this._listener,
    this.flushEvery = const Duration(milliseconds: 200),
  });

  final LiveValuesServiceListener _listener;

  /// How often the buffer is handed to the listener.
  final Duration flushEvery;

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
    for (final k in _subs.keys.toList()) {
      if (!want.contains(k)) {
        unawaited(_subs.remove(k)!.cancel());
      }
    }
    final api = _api;
    if (api == null) {
      return;
    }
    for (final k in want) {
      if (_subs.containsKey(k)) {
        continue;
      }
      _subs[k] = api
          .subscribe(k)
          .listen(
            _onEvent,
            // A refused subscription (rights, a missing key) ends just that
            // key; the others keep running.
            onError: (Object e) => logger.fine('subscribe $k: $e'),
          );
    }
  }

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
