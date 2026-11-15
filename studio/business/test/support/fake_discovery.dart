import 'dart:async';

import 'package:business/redux/services/gateway_browser/gateway_browser.dart';
import 'package:business/wyrm/discovery.dart';
import 'package:wyrm_client/wyrm_client.dart';

// The local network of a test (ADR 0050 §2): a DNS-SD browse that finds
// what the test put in, and `/api/info` answers by origin. Shared by the
// discovery tests of `business` and the log-in tests of `app`.

/// A browse that finds [found] at once.
final class FakeBrowser implements GatewayBrowserBackend {
  FakeBrowser(this.found);

  final List<Announcement> found;

  @override
  Stream<Announcement> browse() {
    // Closed when the browse cancels it.
    // ignore: close_sinks
    late final StreamController<Announcement> c;
    c = StreamController<Announcement>(
      onListen: () {
        found.forEach(c.add);
      },
    );
    return c.stream;
  }
}

/// `/api/info` as a test sets it up, by origin.
final class FakeInfo implements GatewayInfoReader {
  final _infos = <String, GatewayInfo>{};
  final _failures = <String, InfoFailure>{};

  /// Origins whose certificate the system trusts without a pin.
  final trusted = <String>{};

  /// Origins whose certificate chains to a CA of another code than the one
  /// it sends.
  final chainsTo = <String, String>{};

  /// Every unverified read, by URL.
  final unverified = <Uri>[];

  Duration delay = Duration.zero;
  var _now = 0;

  /// The most reads at once.
  var most = 0;

  void serve(List<String> origins, GatewayInfo info) {
    for (final o in origins) {
      _infos[o] = info;
    }
  }

  void fail(String origin, InfoFault fault) =>
      _failures[origin] = InfoFailure(fault, fault.name);

  Future<GatewayInfo> _answer(Uri base) async {
    _now++;
    if (_now > most) {
      most = _now;
    }
    try {
      await Future<void>.delayed(delay);
      if (_failures[base.origin] case final f?) {
        throw f;
      }
      return _infos[base.origin] ??
          (throw const InfoFailure(InfoFault.noAnswer, 'timed out'));
    } finally {
      _now--;
    }
  }

  @override
  Future<GatewayInfo> read(
    Uri base, {
    required GatewayTrust trust,
    String? connectTo,
    Duration timeout = infoTimeout,
  }) async {
    final info = await _answer(base);
    final pin = trust.pinOf(base);
    final chain =
        chainsTo[base.origin] ?? (info.ca == null ? null : caCode(info.ca!));
    if (pin != null ? pin.code == chain : trusted.contains(base.origin)) {
      return info;
    }
    throw const InfoFailure(InfoFault.untrusted, 'CERTIFICATE_VERIFY_FAILED');
  }

  @override
  Future<GatewayInfo> readUnverified(
    Uri base, {
    String? connectTo,
    Duration timeout = infoTimeout,
  }) {
    unverified.add(base);
    return _answer(base);
  }

  @override
  Future<bool> resolves(String host) async => true;

  @override
  Future<LocalNetwork?> localNetwork() async =>
      const LocalNetwork('en0', '10.0.7.12');
}
