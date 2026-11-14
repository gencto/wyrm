import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'found_problem.dart';

part 'found_gateway.freezed.dart';

/// One site found on the local network, by DNS-SD or by a range probe, and
/// checked with its `/api/info` (ADR 0050 §2.3,
/// docs/design/specs/unlock-discover.md §4).
@freezed
abstract class FoundGateway with _$FoundGateway {
  const factory FoundGateway({
    /// The site (`/api/info` `site`, else the TXT `site`).
    required String site,

    /// The hosts as they are shown: `host:port` of the one that answered,
    /// then the standby's.
    @Default(IListConst([])) IList<String> hosts,

    /// The gateway URL to fill in; null when the row cannot be used.
    String? url,

    /// The standby gateway URL (from `pair`, or from a second host that
    /// announced the same site).
    String? standby,

    /// The address to connect to when the URL's name does not resolve on
    /// this computer (ADR 0050 decision 10); null when the name does.
    String? connectTo,

    /// The wyrmd version, when it said.
    String? version,

    /// The gateway serves TLS.
    @Default(true) bool tls,

    /// `active` or `standby` (ADR 0036), as `/api/info` said.
    @Default('active') String role,

    /// The upstream sites of this broker (`up`).
    @Default(IListConst([])) IList<String> up,

    /// The CA code: the first 16 bytes of the SHA-256 of [ca], in hex,
    /// computed here from the certificate that would be pinned.
    String? code,

    /// The CA certificate (DER, base64), as `/api/info` sent it.
    String? ca,

    /// The CA is pinned for the URL's origin or trusted by this computer.
    @Default(false) bool known,

    /// The site whose pinned CA signed this gateway's certificate, when it
    /// is another origin's pin (the person checked that CA before).
    String? knownAs,

    /// Why the row cannot be used; null when it can.
    FoundProblem? problem,

    /// The detail of [problem]: the Studio version a gateway needs, the
    /// reason there was no answer.
    String? detail,

    /// Found by a range probe, not announced.
    @Default(false) bool probed,

    /// When it was last seen, milliseconds since the epoch.
    @Default(0) int seen,
  }) = _FoundGateway;
}
