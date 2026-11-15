import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import 'session.dart';

/// The gateway of the demo's central site (examples/demo/run.sh): what the
/// log-in field holds until the user writes one.
const defaultGateway = 'http://127.0.0.1:8445';

/// A gateway's short name, as the board writes it: the first label of a host
/// name (`plant.local` → `plant`), an address whole (`127.0.0.1`).
String shortHost(Uri uri) {
  final host = uri.host;
  final address = RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':');
  return address ? host : host.split('.').first;
}

/// The label of [gateway] among [among] (it may be in [among] or not), as
/// the log-in page shows it on a recent chip, in the status line and in the
/// first sign-in step (docs/design/specs/login.md §3.2 "Gateway labels"):
///
/// 1. the host is [shortHost], but the whole host name when another gateway
///    has the same short name on another host (`plant.local`,
///    `plant.example`);
/// 2. the port follows when it is not the scheme's default (80, 443), and
///    always when another gateway is on the same host (`127.0.0.1:8445`,
///    `127.0.0.1:8446`; `plant:443` beside `plant:8443`);
/// 3. the scheme comes first when another gateway has the same host and port
///    (`http://plant:8445`, `https://plant:8445`).
///
/// Gateways with the same origin are one gateway. An IPv6 address with a
/// port is written in brackets (`[::1]:8445`).
String gatewayLabel(Uri gateway, Iterable<Uri> among) {
  final others = [
    for (final o in among)
      if (o.origin != gateway.origin) o,
  ];
  final short = shortHost(gateway);
  final host =
      others.any((o) => o.host != gateway.host && shortHost(o) == short)
      ? gateway.host
      : short;
  final sameHost = others.any((o) => o.host == gateway.host);
  // `Uri` drops a port that is the scheme's default: `hasPort` is false.
  final withPort = gateway.hasPort || sameHost;
  final shown = withPort
      ? '${host.contains(':') ? '[$host]' : host}:${gateway.port}'
      : host;
  final sameHostPort = others.any(
    (o) => o.host == gateway.host && o.port == gateway.port,
  );
  return sameHostPort ? '${gateway.scheme}://$shown' : shown;
}

/// The labels of the log-in page's gateways by origin (`gatewayKey`): the
/// main gateway of each [recent] entry and of the [field], each labelled
/// among all of them by [gatewayLabel].
IMap<String, String> labelGateways(Iterable<String> recent, String field) {
  final all = [
    for (final r in [...recent, field]) ...parseGateways(r).take(1),
  ];
  return {for (final g in all) g.origin: gatewayLabel(g, all)}.lock;
}
