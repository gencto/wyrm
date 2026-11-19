import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/answer_fault.dart';
import 'package:models/ca_pin.dart';
import 'package:models/found_gateway.dart';
import 'package:models/found_problem.dart';

import 'discovery.dart';
import 'gateway_label.dart';
import 'session.dart';

// What the log-in page shows, computed from the state (studio-rules §3):
// the gateway field and its probe, the recent gateways, the rows found on
// the network and the range to probe. Typed values; the page words them.

/// The gateway field: one URL, or a main and a standby separated by a
/// comma (ADR 0036). The page shows them as two fields.
final class GatewayField {
  const GatewayField._(this.main, this.standby);

  /// The field's text, the demo gateway while it was never written.
  factory GatewayField.of(String? text) {
    final parts = (text ?? defaultGateway)
        .split(',')
        .map((p) => p.trim())
        .toList();
    final standby = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    return GatewayField._(parts.first, standby);
  }

  /// The main gateway as typed.
  final String main;

  /// The standby gateway as typed; null when none is set.
  final String? standby;

  /// The main gateway's address; null while what is typed is not one.
  GatewayAddress? get mainAddress => parseGateways(main).firstOrNull;

  /// The main gateway's URL; null while what is typed is not one.
  Uri? get mainUri => mainAddress?.uri;

  /// The standby's URL; null without one.
  Uri? get standbyUri =>
      standby == null ? null : parseGateways(standby!).firstOrNull?.uri;

  /// `host:port` of the main gateway; what is typed while it is not a URL.
  String get mainHost => switch (mainUri) {
    final u? => hostPort(u),
    null => main,
  };

  /// `host:port` of the standby; null without one.
  String? get standbyHost => switch (standbyUri) {
    final u? => hostPort(u),
    null => null,
  };

  /// The main gateway speaks TLS.
  bool get https => mainUri?.isScheme('https') ?? false;

  /// The field with [main] in place of the main gateway.
  String withMain(String? main) => _join(main, standby);

  /// The field with [standby] in place of the standby gateway.
  String withStandby(String? standby) => _join(main, standby);

  /// The standby first: *Use the standby*.
  String get swapped => _join(standby, main);

  static String _join(String? a, String? b) => [
    if (a != null && a.isNotEmpty) a,
    if (b != null && b.isNotEmpty) b,
  ].join(', ');
}

/// `host:port` of [uri], as the page writes a gateway's address.
String hostPort(Uri uri) => '${uri.host}:${uri.port}';

/// What the last probe of a gateway found.
enum GatewayReach {
  /// Not probed yet.
  unknown,

  /// It answered.
  answered,

  /// It did not answer.
  down,
}

/// The reach of a probe kept in `login.probes` (milliseconds, -1 for no
/// answer); [GatewayReach.unknown] for none.
GatewayReach reachOf(int? ms) => switch (ms) {
  null => GatewayReach.unknown,
  -1 => GatewayReach.down,
  _ => GatewayReach.answered,
};

/// The state of the field's gateway, as its dot shows it.
enum FieldState {
  /// A picked row's CA waits for the person's check.
  trustPending,

  /// It did not answer.
  down,

  /// Not probed yet.
  unknown,

  /// It answered.
  answered,
}

/// The status line under the gateway field (login.md §3.2).
sealed class FieldNote {
  const FieldNote();
}

/// `<label> · answered in <ms> ms`.
final class FieldAnswered extends FieldNote {
  const FieldAnswered(this.label, this.ms);
  final String label;
  final int ms;
}

/// `No answer from <label>`.
final class FieldNoAnswer extends FieldNote {
  const FieldNoAnswer(this.label);
  final String label;
}

/// `<site> · picked from this network` (with its standby filled in).
final class FieldPicked extends FieldNote {
  const FieldPicked(this.site, {required this.withStandby});
  final String site;
  final bool withStandby;
}

/// The field is empty: type an address or find one.
final class FieldEmpty extends FieldNote {
  const FieldEmpty();
}

/// A recent gateway as its chip shows it.
final class RecentGateway {
  const RecentGateway({
    required this.text,
    required this.label,
    required this.reach,
    required this.current,
  });

  /// The field's text the chip puts back.
  final String text;

  /// Its label among the others (`gatewayLabel`).
  final String label;
  final GatewayReach reach;

  /// The field holds it.
  final bool current;
}

/// The recent gateways of [recent] as chips: [labels] by origin, [probes]
/// by origin, and the [field]'s text to mark the current one.
List<RecentGateway> recentGatewaysOf(
  IList<String> recent,
  IMap<String, String> labels,
  IMap<String, int> probes,
  String field,
) => [
  for (final r in recent)
    if (parseGateways(r).firstOrNull case final u?)
      RecentGateway(
        text: r,
        label: labels[u.origin] ?? shortHost(u.uri),
        reach: reachOf(probes[u.origin]),
        current: r == field.trim(),
      ),
];

/// What the footer's TLS line says of the field's gateway.
sealed class TlsLine {
  const TlsLine();
}

/// The CA of the picked row [site] is not trusted yet.
final class TlsNotTrusted extends TlsLine {
  const TlsNotTrusted(this.site);
  final String site;
}

/// Its CA is pinned, for [site].
final class TlsPinned extends TlsLine {
  const TlsPinned(this.site);
  final String site;
}

/// An `https` gateway: the certificate of [site]'s CA.
final class TlsCertificate extends TlsLine {
  const TlsCertificate(this.site);
  final String site;
}

/// What is known of a found row's CA (its note after the version).
sealed class FoundKnown {
  const FoundKnown();
}

/// Plain HTTP on this computer: no CA at all.
final class FoundPlain extends FoundKnown {
  const FoundPlain();
}

/// Its CA is pinned, for [site].
final class FoundPinned extends FoundKnown {
  const FoundPinned(this.site);
  final String site;
}

/// This computer trusts its certificate.
final class FoundTrusted extends FoundKnown {
  const FoundTrusted();
}

/// Signed by the CA pinned for [site].
final class FoundKnownAs extends FoundKnown {
  const FoundKnownAs(this.site);
  final String site;
}

/// Its own CA, not known here: check the code first.
final class FoundFresh extends FoundKnown {
  const FoundFresh();
}

/// A found gateway as its row in *Find on this network* shows it.
final class FoundRow {
  const FoundRow({
    required this.site,
    required this.tags,
    required this.host,
    required this.standbyHost,
    required this.version,
    required this.known,
    required this.problem,
    required this.detail,
    required this.why,
    required this.up,
    required this.seen,
    required this.selected,
    required this.enabled,
  });

  final String site;
  final List<FoundTag> tags;

  /// `host:port` of the host that answered (the site when none did).
  final String host;

  /// `host:port` of its standby, when it has one.
  final String? standbyHost;

  /// The wyrmd version, when it said.
  final String? version;
  final FoundKnown known;

  /// Why it cannot be picked, with its [detail]; null when it can.
  final FoundProblem? problem;
  final String detail;

  /// Why `/api/info` gave nothing, when that is the problem.
  final AnswerFault? why;

  /// The sites it is a downstream of.
  final List<String> up;

  /// How long ago it was last seen, in whole seconds.
  final Duration seen;

  /// It is the row picked.
  final bool selected;

  /// It can be picked.
  final bool enabled;

  /// A CA not known here: the row is marked new.
  bool get fresh => tags.contains(FoundTag.fresh);
}

/// The rows of [found] at [now], usable first, then by site.
List<FoundRow> foundRowsAt(
  Iterable<FoundGateway> found, {
  required IList<String> recent,
  required IMap<String, CaPin> pins,
  required String? picked,
  required DateTime now,
}) {
  final rows = found.toList()
    ..sort((a, b) {
      final ua = a.problem == null ? 0 : 1;
      final ub = b.problem == null ? 0 : 1;
      return ua != ub ? ua - ub : a.site.compareTo(b.site);
    });
  return [
    for (final r in rows)
      _rowOf(r, recent: recent, pins: pins, picked: picked, now: now),
  ];
}

FoundRow _rowOf(
  FoundGateway r, {
  required IList<String> recent,
  required IMap<String, CaPin> pins,
  required String? picked,
  required DateTime now,
}) {
  final standby = r.standby == null ? null : Uri.tryParse(r.standby!);
  final url = r.url == null ? null : Uri.tryParse(r.url!);
  final pinned = url == null ? null : pins[url.origin];
  final seen = now.millisecondsSinceEpoch - r.seen;
  return FoundRow(
    site: r.site,
    tags: tagsOf(r, recent),
    host: r.hosts.isEmpty ? r.site : r.hosts.first,
    standbyHost: standby == null ? null : hostPort(standby),
    version: r.version == null || r.version!.isEmpty ? null : r.version,
    known: switch (r) {
      _ when !r.tls => const FoundPlain(),
      _ when pinned != null => FoundPinned(
        pinned.site.isEmpty ? r.site : pinned.site,
      ),
      _ when r.known => const FoundTrusted(),
      FoundGateway(:final knownAs?) => FoundKnownAs(knownAs),
      _ => const FoundFresh(),
    },
    problem: r.problem,
    detail: r.detail ?? '',
    why: r.why,
    up: r.up.toList(),
    seen: Duration(seconds: seen < 0 ? 0 : seen ~/ 1000),
    selected: picked == r.site,
    enabled: r.problem == null && r.url != null,
  );
}

/// The port *Probe a range* uses until one is typed: the port of the
/// gateway in the [field], else the gateway's default.
int defaultProbePortOf(String? field) =>
    parseGateways(field ?? '').firstOrNull?.uri.port ?? defaultGatewayPort;

/// The port a WYRM gateway listens on by default.
const defaultGatewayPort = 8446;

/// What is wrong with [range]; null when it can be probed.
RangeFault? rangeFaultOf(String range) {
  try {
    rangeAddresses(range);
    return null;
  } on RangeFormatException catch (e) {
    return e.fault;
  }
}

/// The port of *Probe a range*, or null when [port] is not one (1–65535).
int? probePortOf(String port) {
  final p = int.tryParse(port);
  return p == null || p < 1 || p > 65535 ? null : p;
}

/// `user:olena@plant` → `olena`.
String userNameOf(String subject) {
  final name = subject.startsWith('user:') ? subject.substring(5) : subject;
  final at = name.indexOf('@');
  return at < 0 ? name : name.substring(0, at);
}
