import 'dart:async';

import '../../../common/services/interface.dart';

abstract class IdleLockServiceListener {
  /// Nobody used Studio for the lock delay.
  void onIdle();
}

/// The clock of the idle lock (ADR 0050 §1.4, unlock-discover.md §3): a
/// timer of [delay] that every [touch] starts again. When it runs out, the
/// listener locks Studio. A zero [delay] is off.
///
/// The shell calls [touch] on the person's pointer and keys (throttled), not
/// on values that change by themselves.
class IdleLockService extends DisposableServiceInterface {
  IdleLockService({required this._listener});

  final IdleLockServiceListener _listener;

  Timer? _timer;
  Duration _delay = Duration.zero;

  /// The lock delay in force; zero when the lock is off.
  Duration get delay => _delay;

  /// Starts the clock again with [delay]; zero stops it.
  void arm(Duration delay) {
    _delay = delay;
    touch();
  }

  /// The person did something: the clock starts again.
  void touch() {
    _timer?.cancel();
    _timer = _delay > Duration.zero ? Timer(_delay, _listener.onIdle) : null;
  }

  /// Stops the clock (a log out, a lock).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> start() async {
    await super.start();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    stop();
  }
}
