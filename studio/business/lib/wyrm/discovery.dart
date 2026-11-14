import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/ca_pin.dart';
import 'package:models/found_gateway.dart';
import 'package:models/found_problem.dart';
import 'package:wyrm_client/wyrm_client.dart';

// Finding a gateway on the local network and trusting its CA (ADR 0050 §2,
// decisions 10–12; docs/design/specs/unlock-discover.md §4). The rules a
// person cannot see are here, as plain functions, so they are tested
// without a network: how a row's URL is made from an address and the
// certificate's names, when a row is greyed out, how rows of one site
// merge, and how a range is read.

/// This Studio's version, against `/api/info` `min_studio`. It moves with
/// `version:` in `app/pubspec.yaml` (a test in `app` checks that).
const studioRelease = '1.0.0';

/// How long *Find on this network* browses (ADR 0050 §2.3).
const browseFor = Duration(seconds: 8);

/// The service a gateway announces.
const wyrmService = '_wyrm._tcp';

/// *Probe a range*: at most this many addresses in a range, this many
/// requests at a time, and this long for each one.
const rangeLimit = 1024;
const rangeAtOnce = 16;
const rangeTimeout = Duration(milliseconds: 1500);

/// How long a row's `/api/info` may take.
const infoTimeout = Duration(seconds: 3);

/// One DNS-SD answer for `_wyrm._tcp`, resolved; or one address of a range
/// probe, with no TXT record.
final class Announcement {
  const Announcement({
    required this.name,
    required this.port,
    this.hostname,
    this.addresses = const [],
    this.txt = const {},
    this.probed = false,
  });

  /// The instance name (the site, ADR 0050 §2.1).
  final String name;

  /// The mDNS host name (`plant.local`), when the platform gives one.
  final String? hostname;

  /// The addresses the platform resolved.
  final List<String> addresses;
  final int port;

  /// The TXT record: `v, site, tls, fp, role, pair, up`.
  final Map<String, String> txt;

  /// From a range probe: it said nothing before its `/api/info`.
  final bool probed;

  String get site => txt['site'] ?? name;

  @override
  String toString() =>
      'Announcement($name ${hostname ?? ''} $addresses:$port $txt)';
}

/// What went wrong reading `/api/info`.
enum InfoFault {
  /// TLS, with a certificate this client does not trust.
  untrusted,

  /// The port does not speak TLS.
  notTls,

  /// Something answered, but not `/api/info`: a wyrmd from before ADR 0050,
  /// or not a gateway at all.
  missing,

  /// No answer.
  noAnswer,
}

final class InfoFailure implements Exception {
  const InfoFailure(this.fault, [this.reason = '']);

  final InfoFault fault;
  final String reason;

  @override
  String toString() => 'InfoFailure(${fault.name}: $reason)';
}

/// The CA pins in force: every `https` connection to a pinned origin
/// trusts that CA and nothing else; any other origin trusts the system's
/// roots. A pin with `connectTo` also says where its name is
/// (ADR 0050 decision 10).
final class GatewayTrust {
  const GatewayTrust([this.pins = const IMapConst({})]);

  /// By origin, `https://host:port`.
  final IMap<String, CaPin> pins;

  CaPin? pinOf(Uri gateway) => pins[gateway.origin];

  /// The same trust with [more] pinned too.
  GatewayTrust plus(Iterable<CaPin> more) =>
      GatewayTrust(pins.addAll({for (final p in more) p.origin: p}.lock));

  /// An HTTP client for gateways under this trust. [via] adds addresses to
  /// connect to for origins whose name does not resolve, beside the pins'.
  /// One client serves the main gateway and its standby (`loginAny`), each
  /// origin with its own pin.
  HttpClient client({
    Duration? timeout,
    Map<String, String> via = const {},
  }) {
    final c = HttpClient()..connectionTimeout = timeout;
    if (pins.isEmpty && via.isEmpty) {
      return c;
    }
    c.connectionFactory = (uri, _, _) {
      final pin = pins[uri.origin];
      return _connect(
        uri,
        to: via[uri.origin] ?? pin?.connectTo,
        context: pin == null ? null : _contextOf(pin.ca),
        timeout: timeout,
      );
    };
    return c;
  }

  static final _contexts = <String, SecurityContext>{};

  /// A context that trusts the CA of [ca] (DER, base64) alone: a
  /// `SecurityContext` starts with no trusted roots.
  static SecurityContext _contextOf(String ca) => _contexts.putIfAbsent(
    ca,
    () =>
        SecurityContext()
          ..setTrustedCertificatesBytes(utf8.encode(pemOf(base64Decode(ca)))),
  );
}

/// A client that accepts any certificate. Only for `GET /api/info`, which
/// carries no secret, to show a CA the person has not checked yet; never
/// for a login or with a session.
HttpClient unverifiedClient({Duration? timeout, String? connectTo}) {
  final c = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (_, _, _) => true;
  if (connectTo != null) {
    c.connectionFactory = (uri, _, _) =>
        _connect(uri, to: connectTo, timeout: timeout, anyCertificate: true);
  }
  return c;
}

/// Opens a connection to [to] (else the URL's host) and, for `https`,
/// checks the certificate against the URL's host, under [context].
/// `HttpClient` does not wrap a socket a factory returns in TLS, so this
/// does.
Future<ConnectionTask<Socket>> _connect(
  Uri uri, {
  String? to,
  SecurityContext? context,
  Duration? timeout,
  bool anyCertificate = false,
}) async {
  final task = await Socket.startConnect(to ?? uri.host, uri.port);
  var socket = task.socket;
  if (timeout != null) {
    socket = socket.timeout(
      timeout,
      onTimeout: () {
        task.cancel();
        throw TimeoutException('connect', timeout);
      },
    );
  }
  if (uri.scheme != 'https') {
    return ConnectionTask.fromSocket(socket, task.cancel);
  }
  return ConnectionTask.fromSocket(
    socket.then(
      (s) => SecureSocket.secure(
        s,
        host: uri.host,
        context: context,
        onBadCertificate: anyCertificate ? (_) => true : null,
      ),
    ),
    task.cancel,
  );
}

/// [der] as one PEM certificate (`SecurityContext` takes PEM, not DER).
String pemOf(List<int> der) {
  final b64 = base64Encode(der);
  final lines = [
    for (var i = 0; i < b64.length; i += 64)
      b64.substring(i, i + 64 > b64.length ? b64.length : i + 64),
  ];
  return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
      '-----END CERTIFICATE-----\n';
}

/// The CA code: the first 16 bytes of the SHA-256 of the certificate, in
/// lower-case hex (ADR 0050 decision 11).
String caCode(List<int> der) => sha256
    .convert(der)
    .bytes
    .take(16)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// [code] as the person compares it: 8 groups of 4, upper case.
List<String> codeGroups(String code) => [
  for (var i = 0; i + 4 <= code.length; i += 4)
    code.substring(i, i + 4).toUpperCase(),
];

/// Reads `/api/info`; the seam tests replace.
abstract interface class GatewayInfoReader {
  /// `GET <base>/api/info` under [trust] (pins and the system's roots).
  /// Throws an [InfoFailure].
  Future<GatewayInfo> read(
    Uri base, {
    required GatewayTrust trust,
    String? connectTo,
    Duration timeout,
  });

  /// The same read, accepting any certificate ([unverifiedClient]).
  Future<GatewayInfo> readUnverified(
    Uri base, {
    String? connectTo,
    Duration timeout,
  });

  /// [host] resolves on this computer.
  Future<bool> resolves(String host);

  /// The interface Studio browses on, for the panel title and the default
  /// range; null when there is none.
  Future<LocalNetwork?> localNetwork();
}

/// The first usable IPv4 interface: its name and the /24 around it. Dart
/// does not give an interface's prefix length, and a Wi-Fi name (SSID)
/// needs location permission on iOS and Android, so neither is shown.
final class LocalNetwork {
  const LocalNetwork(this.interface, this.address);

  final String interface;
  final String address;

  /// `10.0.7.0/24`.
  String get subnet {
    final p = address.split('.');
    return '${p[0]}.${p[1]}.${p[2]}.0/24';
  }
}

/// The real reader: `dart:io`.
final class HttpInfoReader implements GatewayInfoReader {
  const HttpInfoReader();

  @override
  Future<GatewayInfo> read(
    Uri base, {
    required GatewayTrust trust,
    String? connectTo,
    Duration timeout = infoTimeout,
  }) => _get(
    trust.client(
      timeout: timeout,
      via: connectTo == null ? const {} : {base.origin: connectTo},
    ),
    base,
    timeout,
  );

  @override
  Future<GatewayInfo> readUnverified(
    Uri base, {
    String? connectTo,
    Duration timeout = infoTimeout,
  }) => _get(
    unverifiedClient(timeout: timeout, connectTo: connectTo),
    base,
    timeout,
  );

  static Future<GatewayInfo> _get(
    HttpClient http,
    Uri base,
    Duration timeout,
  ) async {
    try {
      final req = await http.getUrl(base.resolve('/api/info')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final bytes = await res
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, c) => b..add(c))
          .timeout(timeout);
      if (res.statusCode != HttpStatus.ok) {
        throw InfoFailure(
          res.statusCode == HttpStatus.notFound
              ? InfoFault.missing
              : InfoFault.noAnswer,
          'HTTP ${res.statusCode}',
        );
      }
      try {
        return GatewayInfo.of(Value.fromCbor(bytes.takeBytes()));
      } on Object {
        throw const InfoFailure(InfoFault.missing, 'not a WYRM gateway');
      }
    } on InfoFailure {
      rethrow;
    } on TlsException catch (e) {
      final s = '$e';
      throw InfoFailure(
        s.contains('WRONG_VERSION_NUMBER') || s.contains('PACKET_LENGTH')
            ? InfoFault.notTls
            : InfoFault.untrusted,
        e.message,
      );
    } on TimeoutException {
      throw const InfoFailure(InfoFault.noAnswer, 'timed out');
    } on SocketException catch (e) {
      throw InfoFailure(InfoFault.noAnswer, e.message);
    } on HttpException catch (e) {
      // A TLS client on a plain port, or the reverse, often ends here.
      throw InfoFailure(
        base.scheme == 'https' ? InfoFault.notTls : InfoFault.missing,
        e.message,
      );
    } on Object catch (e) {
      throw InfoFailure(InfoFault.noAnswer, '$e');
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<bool> resolves(String host) async {
    if (InternetAddress.tryParse(host) != null) {
      return true;
    }
    try {
      final found = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 2));
      return found.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<LocalNetwork?> localNetwork() async {
    try {
      final all = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in all) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) {
            return LocalNetwork(i.name, a.address);
          }
        }
      }
    } on Object {
      // No interfaces to read: the panel says less.
    }
    return null;
  }
}

/// The host of [address] for a URL authority: IPv6 in brackets.
String authorityHost(String address) =>
    address.contains(':') && !address.startsWith('[') ? '[$address]' : address;

/// The address to use from [addresses]: IPv4 first, then a global IPv6
/// (a link-local one needs a zone a URL cannot carry).
String? pickAddress(List<String> addresses) {
  final parsed = [
    for (final a in addresses) ?InternetAddress.tryParse(a),
  ];
  return parsed
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull
          ?.address ??
      parsed
          .where((a) => a.type == InternetAddressType.IPv6 && !a.isLinkLocal)
          .firstOrNull
          ?.address;
}

bool _isLoopback(String host) {
  final h = host.startsWith('[') ? host.substring(1, host.length - 1) : host;
  return h == 'localhost' || (InternetAddress.tryParse(h)?.isLoopback ?? false);
}

bool _isAddress(String name) => InternetAddress.tryParse(name) != null;

/// [have] is [need] or newer (numeric `a.b.c`; a missing part is 0).
bool atLeast(String have, String need) {
  List<int> parts(String v) => [
    for (final p in v.split(RegExp('[.+-]')).take(3)) int.tryParse(p) ?? 0,
  ];
  final a = parts(have);
  final b = parts(need);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) {
      return x > y;
    }
  }
  return true;
}

/// The URL a found row is reached at, from its address and the names of
/// its certificate (ADR 0050 decision 10): the address itself when the
/// certificate lists it, else the mDNS host name when listed, else the
/// first DNS name. `connectTo` is the address when that name does not
/// resolve here. Null when the certificate names neither: the person types
/// the address instead.
Future<({Uri url, String? connectTo})?> urlFromNames({
  required String address,
  required int port,
  required List<String> names,
  required Future<bool> Function(String host) resolves,
  String? hostname,
}) async {
  Uri at(String host) => Uri(
    scheme: 'https',
    host: host.replaceAll(RegExp(r'[\[\]]'), ''),
    port: port,
  );
  if (names.contains(address)) {
    return (url: at(address), connectTo: null);
  }
  final mdns = hostname?.replaceFirst(RegExp(r'\.$'), '');
  final dns = [
    if (mdns != null && names.contains(mdns)) mdns,
    for (final n in names)
      if (!_isAddress(n) && !n.startsWith('*')) n,
  ];
  if (dns.isEmpty) {
    return null;
  }
  final name = dns.first;
  return (
    url: at(name),
    connectTo: await resolves(name) ? null : address,
  );
}

/// Checks one announcement (or one probed address) with its `/api/info`
/// and makes its row; null when nothing answered a range probe (an empty
/// address is not a row).
Future<FoundGateway?> checkFound(
  Announcement a, {
  required GatewayInfoReader reader,
  required GatewayTrust trust,
  required int now,
  String studio = studioRelease,
}) async {
  final address =
      pickAddress(a.addresses) ?? a.hostname?.replaceFirst(RegExp(r'\.$'), '');
  if (address == null) {
    return null;
  }
  final host = authorityHost(address);
  final hostPort = '$host:${a.port}';
  final timeout = a.probed ? rangeTimeout : infoTimeout;
  final txtFp = a.txt['fp']?.toLowerCase();
  final txtTls = a.txt['tls'];

  FoundGateway row(
    String site, {
    FoundProblem? problem,
    String? detail,
    bool tls = true,
  }) => FoundGateway(
    site: site,
    hosts: [hostPort].lock,
    tls: tls,
    version: a.txt['v'],
    up: _upOf(a.txt['up']),
    standby: _standbyOf(a.txt['pair'], tls: tls),
    problem: problem,
    detail: detail,
    probed: a.probed,
    seen: now,
  );

  // Plain HTTP: announced with `tls=0`, or a probed port that is not TLS.
  Future<FoundGateway?> plain() async {
    final url = Uri.parse('http://$hostPort');
    try {
      final info = await reader.readUnverified(url, timeout: timeout);
      final loopback = _isLoopback(host);
      final w = _withInfo(
        row(info.site.isEmpty ? a.site : info.site, tls: false),
        info,
        studio,
      );
      return w.copyWith(
        url: loopback ? '$url' : null,
        problem: loopback ? w.problem : FoundProblem.plainHttp,
        detail: loopback ? w.detail : null,
        known: loopback,
      );
    } on InfoFailure catch (e) {
      return a.probed ? null : _failed(row(a.site, tls: false), e);
    }
  }

  if (txtTls == '0') {
    return plain();
  }

  final GatewayInfo info;
  try {
    info = await reader.readUnverified(
      Uri.parse('https://$hostPort'),
      timeout: timeout,
    );
  } on InfoFailure catch (e) {
    if (e.fault == InfoFault.notTls) {
      return plain();
    }
    return a.probed ? null : _failed(row(a.site), e);
  }

  final site = info.site.isEmpty ? a.site : info.site;
  var found = _withInfo(row(site), info, studio);
  final ca = info.ca;
  final code = ca == null ? null : caCode(ca);
  found = found.copyWith(
    code: code,
    ca: ca == null ? null : base64Encode(ca),
  );
  final claimed = info.caFp?.toLowerCase();
  if (code != null &&
      ((claimed != null && claimed != code) ||
          (txtFp != null && txtFp != code))) {
    // A code that is not the CA's it sent: nothing here can be trusted.
    return found.copyWith(problem: FoundProblem.codeMismatch, detail: null);
  }

  final reach = await urlFromNames(
    address: address,
    port: a.port,
    names: info.names,
    hostname: a.hostname,
    resolves: reader.resolves,
  );
  if (reach == null) {
    return found.copyWith(problem: found.problem ?? FoundProblem.noName);
  }
  found = found.copyWith(url: '${reach.url}', connectTo: reach.connectTo);

  // Known: the CA is pinned for this origin, or the system trusts it and
  // the name resolves (a name that does not needs a pin, which keeps the
  // address to connect to).
  var strict = true;
  try {
    await reader.read(
      reach.url,
      trust: trust,
      connectTo: reach.connectTo,
      timeout: timeout,
    );
  } on InfoFailure {
    strict = false;
  }
  final known =
      strict && (trust.pinOf(reach.url) != null || reach.connectTo == null);
  final other = known
      ? null
      : trust.pins.values
            .where((p) => p.code == code && p.origin != reach.url.origin)
            .firstOrNull;
  return found.copyWith(
    known: known,
    knownAs: other?.site,
    // Without its CA, a certificate this computer cannot use as it is
    // cannot be pinned either (ADR 0050 decision 11: no code).
    problem: !known && code == null
        ? found.problem ?? FoundProblem.noCa
        : found.problem,
  );
}

FoundGateway _withInfo(FoundGateway row, GatewayInfo info, String studio) {
  final up = info.up.isNotEmpty ? info.up.toIList() : row.up;
  return row.copyWith(
    version: info.version.isEmpty ? row.version : info.version,
    up: up,
    role: info.role,
    standby: _standbyOf(info.pair, tls: row.tls) ?? row.standby,
    problem: atLeast(studio, info.minStudio) ? null : FoundProblem.studioTooOld,
    detail: atLeast(studio, info.minStudio) ? null : info.minStudio,
  );
}

FoundGateway _failed(FoundGateway row, InfoFailure e) => row.copyWith(
  problem: e.fault == InfoFault.missing
      ? FoundProblem.noInfo
      : FoundProblem.noAnswer,
  detail: e.reason,
);

IList<String> _upOf(String? up) => [
  for (final s in (up ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
].lock;

String? _standbyOf(String? pair, {required bool tls}) =>
    pair == null || pair.trim().isEmpty
    ? null
    : '${tls ? 'https' : 'http'}://${pair.trim()}';

/// [row] merged into [found] by its site: an active and its standby are one
/// row (ADR 0050 §2.3). A second host of a site becomes the standby of the
/// one that says `role: active`; the same host again replaces its row.
IMap<String, FoundGateway> mergeFound(
  IMap<String, FoundGateway> found,
  FoundGateway row,
) {
  final had = found[row.site];
  if (had == null || had.hosts.any(row.hosts.contains)) {
    return found.add(
      row.site,
      row.copyWith(standby: row.standby ?? had?.standby),
    );
  }
  // A usable row wins over one that cannot be used, then the active.
  final rowFirst =
      (had.problem != null && row.problem == null) ||
      (had.problem == null) == (row.problem == null) &&
          row.role == 'active' &&
          had.role != 'active';
  final (main, other) = rowFirst ? (row, had) : (had, row);
  return found.add(
    row.site,
    main.copyWith(
      standby: main.standby ?? other.url,
      hosts: [
        ...main.hosts,
        ...other.hosts.where((h) => !main.hosts.contains(h)),
      ].lock,
      seen: row.seen > had.seen ? row.seen : had.seen,
    ),
  );
}

/// What is wrong with a range, for the line under its field.
enum RangeFault { badText, badPart, badPrefix, tooBig }

final class RangeFormatException extends FormatException {
  const RangeFormatException(this.fault, String message) : super(message);

  final RangeFault fault;
}

/// The addresses of an IPv4 range (`10.0.7.0/24`, or one address), at most
/// [rangeLimit]; the network and broadcast addresses of a block are left
/// out (below /31). Throws a [RangeFormatException] with the reason.
List<String> rangeAddresses(String text) {
  final m = RegExp(
    r'^\s*(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?\s*$',
  ).firstMatch(text);
  if (m == null) {
    throw const RangeFormatException(
      RangeFault.badText,
      'Write an IPv4 range, as 10.0.7.0/24.',
    );
  }
  final octets = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (octets.any((o) => o > 255)) {
    throw const RangeFormatException(
      RangeFault.badPart,
      'Each part of an address is 0 to 255.',
    );
  }
  final prefix = int.parse(m.group(5) ?? '32');
  if (prefix > 32) {
    throw const RangeFormatException(
      RangeFault.badPrefix,
      'The prefix is 0 to 32.',
    );
  }
  final size = 1 << (32 - prefix);
  if (size > rangeLimit) {
    throw const RangeFormatException(
      RangeFault.tooBig,
      'At most $rangeLimit addresses: a /22 or smaller.',
    );
  }
  final ip = octets.fold<int>(0, (v, o) => (v << 8) | o);
  final base = ip & ~(size - 1) & 0xFFFFFFFF;
  final edges = size >= 4;
  return [
    for (var i = edges ? 1 : 0; i < (edges ? size - 1 : size); i++)
      [
        for (var s = 24; s >= 0; s -= 8) ((base + i) >> s) & 0xFF,
      ].join('.'),
  ];
}

/// Runs [work] on each of [items], [atOnce] at a time.
Future<void> pooled<T>(
  List<T> items,
  Future<void> Function(T item) work, {
  int atOnce = rangeAtOnce,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      await work(item);
    }
  }

  await Future.wait([
    for (var i = 0; i < atOnce && i < items.length; i++) worker(),
  ]);
}

/// The code a broker's System › Gateway page shows as a QR:
/// `wyrm://host:port?fp=<32 hex>` → the gateway URL and the CA code. Null
/// when [text] is not one.
({Uri url, String code})? parseGatewayCode(String text) {
  final u = Uri.tryParse(text.trim());
  if (u == null || u.scheme != 'wyrm' || u.host.isEmpty || !u.hasPort) {
    return null;
  }
  final fp = (u.queryParameters['fp'] ?? '')
      .replaceAll(RegExp(r'[\s:-]'), '')
      .toLowerCase();
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(fp)) {
    return null;
  }
  return (url: Uri(scheme: 'https', host: u.host, port: u.port), code: fp);
}

/// The pins that trusting [row] adds: its origin (with the address to
/// connect to), and its standby's.
List<CaPin> pinsFor(FoundGateway row) {
  final url = Uri.parse(row.url!);
  return [
    CaPin(
      origin: url.origin,
      ca: row.ca!,
      code: row.code!,
      site: row.site,
      connectTo: row.connectTo,
    ),
    if (row.standby case final s? when Uri.tryParse(s)?.scheme == 'https')
      CaPin(
        origin: Uri.parse(s).origin,
        ca: row.ca!,
        code: row.code!,
        site: row.site,
      ),
  ];
}

/// The tags of a found row (docs/design/specs/unlock-discover.md §4).
enum FoundTag {
  /// Its origin is among the recent gateways.
  usedBefore,

  /// An active with a standby.
  activeStandby,

  /// A downstream of the sites in `up`.
  downstream,

  /// A CA neither pinned nor trusted by this computer (`new`).
  fresh,

  /// Plain `http` off loopback; the row is disabled.
  plainHttp,
}

/// The tags of [row], in the order the row shows them. [recent] are the
/// recent gateways as the log-in page keeps them (each one a `main,
/// standby` list); a row is used before when its URL's origin is in one.
List<FoundTag> tagsOf(FoundGateway row, Iterable<String> recent) {
  final origin = row.url == null ? null : Uri.tryParse(row.url!)?.origin;
  final used =
      origin != null &&
      recent.any(
        (r) => r
            .split(',')
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .map((g) => Uri.tryParse(g.contains('://') ? g : 'http://$g'))
            .any((u) => u != null && u.hasAuthority && u.origin == origin),
      );
  return [
    if (used) FoundTag.usedBefore,
    if (row.standby != null) FoundTag.activeStandby,
    if (row.up.isNotEmpty) FoundTag.downstream,
    if (row.tls && !row.known && row.knownAs == null && row.problem == null)
      FoundTag.fresh,
    if (row.problem == FoundProblem.plainHttp) FoundTag.plainHttp,
  ];
}
