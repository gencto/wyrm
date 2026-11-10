import 'dart:async';

import '../../../common/services/interface.dart';

abstract class TrafficServiceListener {
  /// Time to look at the router rates again.
  void onTick();
}

/// The clock of the Overview's traffic ring: a tick every [every] while
/// Studio runs, whatever screen is shown (the broker keeps no history of
/// its rates, so Studio samples them; specs/system.md, Traffic).
class TrafficService extends DisposableServiceInterface {
  TrafficService({
    required this._listener,
    this.every = const Duration(seconds: 2),
  });

  final TrafficServiceListener _listener;

  /// Shorter than any metrics interval in use, so no sample is missed; a
  /// tick without a new sample changes nothing.
  final Duration every;

  Timer? _timer;

  @override
  Future<void> start() async {
    super.start();
    _timer ??= Timer.periodic(every, (_) => _listener.onTick());
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    _timer?.cancel();
    _timer = null;
  }
}
