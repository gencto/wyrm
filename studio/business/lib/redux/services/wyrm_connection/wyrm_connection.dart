import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../../common/services/interface.dart';

/// What [WyrmConnectionService] tells its listener.
abstract class WyrmConnectionServiceListener {
  /// The gateway WebSocket opened ([connected] true) or was lost (false;
  /// the client reconnects by itself, ADR 0006).
  void onConnection({required bool connected});
}

/// Follows the `connection` stream of the session's reconnecting client.
///
/// [attach] starts following a session's stream, [detach] stops; the service
/// lives as long as the store, a session only as long as a login.
class WyrmConnectionService extends DisposableServiceInterface {
  WyrmConnectionService({required this._listener});

  final WyrmConnectionServiceListener _listener;
  StreamSubscription<bool>? _sub;
  bool? _last;

  /// The last state reported, or null before a session.
  bool? get connected => _last;

  /// Follows [connection] (the session's `ReconnectingClient.connection`).
  void attach(Stream<bool> connection) {
    unawaited(_sub?.cancel());
    _last = null;
    _sub = connection.listen(_report);
  }

  void _report(bool connected) {
    if (_last == connected) {
      return;
    }
    _last = connected;
    _listener.onConnection(connected: connected);
  }

  /// Stops following the session's stream.
  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
    _last = null;
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await detach();
  }
}

/// A WyrmApi call that failed because the socket was cut while it ran.
bool isDisconnect(Object e) =>
    e is WyrmException && e.status == StatusCode.of(Status.disconnected);
