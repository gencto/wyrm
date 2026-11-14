import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../../../common/services/interface.dart';
import '../../../wyrm/discovery.dart';

/// What the service needs from whoever is listening. Declared here, beside the
/// class that calls it, so the dependency points from the listener to the
/// service — this half knows nothing of Redux.
abstract class GatewayBrowserServiceListener {
  /// [found] answered browse number [scan].
  void onFound(Announcement found, int scan);
}

/// The DNS-SD side: a stream of resolved `_wyrm._tcp` services while it is
/// listened to. Tests pass a fake.
abstract interface class GatewayBrowserBackend {
  Stream<Announcement> browse();
}

/// Browses `_wyrm._tcp` for a while and hands each resolved service to the
/// listener (ADR 0050 §2.3, *Find on this network*). One browse at a time:
/// a new one ends the last.
class GatewayBrowserService extends DisposableServiceInterface {
  GatewayBrowserService({
    required this._listener,
    GatewayBrowserBackend? backend,
    this.duration = browseFor,
  }) : _backend = backend ?? const BonsoirBrowser();

  final GatewayBrowserServiceListener _listener;
  final GatewayBrowserBackend _backend;

  /// How long one browse lasts.
  final Duration duration;

  // Cancelled by [stop], when the browse ends or a new one starts.
  // ignore: cancel_subscriptions
  StreamSubscription<Announcement>? _browse;
  Completer<void>? _ended;
  Timer? _timer;

  /// Browses for [duration], tagging what it finds with [scan]; completes
  /// when the browse ends (its time is up, the platform stopped it, or
  /// [stop] or a new browse ended it). Never throws: a platform that cannot
  /// browse finds nothing, which the panel explains.
  Future<void> browse(int scan) async {
    await stop();
    final ended = _ended = Completer<void>();
    void end() {
      if (!ended.isCompleted) {
        ended.complete();
      }
    }

    _browse = _backend.browse().listen(
      (a) => _listener.onFound(a, scan),
      onError: (Object _) => end(),
      onDone: end,
    );
    _timer = Timer(duration, () => unawaited(stop()));
    await ended.future;
  }

  /// Ends the browse in progress, if any.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final b = _browse;
    _browse = null;
    final e = _ended;
    _ended = null;
    if (e != null && !e.isCompleted) {
      e.complete();
    }
    await b?.cancel();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await stop();
  }
}

/// The real browse, through `bonsoir` (Bonjour on Apple platforms, NSD on
/// Android with its multicast lock, Avahi on Linux, DNS-SD on Windows).
final class BonsoirBrowser implements GatewayBrowserBackend {
  const BonsoirBrowser();

  @override
  Stream<Announcement> browse() {
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? events;
    late final StreamController<Announcement> out;
    out = StreamController<Announcement>(
      onListen: () async {
        try {
          final d = discovery = BonsoirDiscovery(type: wyrmService);
          await d.initialize();
          events = d.eventStream?.listen((e) {
            switch (e) {
              case BonsoirDiscoveryServiceFoundEvent(:final service):
                unawaited(
                  Future.sync(() => d.serviceResolver.resolveService(service)),
                );
              case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
                  BonsoirDiscoveryServiceUpdatedEvent(:final service):
                out.add(announcementOf(service));
              case BonsoirDiscoveryStoppedEvent():
                unawaited(out.close());
              default:
            }
          });
          await d.start();
        } on Object catch (e) {
          out.addError(e);
          await out.close();
        }
      },
      onCancel: () async {
        await events?.cancel();
        try {
          await discovery?.stop();
        } on Object {
          // Already stopped.
        }
      },
    );
    return out.stream;
  }

  static Announcement announcementOf(BonsoirService s) => Announcement(
    name: s.name,
    hostname: s.hostname,
    addresses: s.hostAddresses,
    port: s.port,
    txt: s.attributes,
  );
}
