import 'dart:convert';

import 'package:async_redux/async_redux.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/discovery.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Why a trust was refused (`discovery.trustRefused`); the card says it in
/// the person's language.
abstract final class TrustRefusal {
  /// The gateway did not answer the second read.
  static const noAnswer = 'no_answer';

  /// The CA it sends now is not the one whose code was shown.
  static const changed = 'changed';

  /// Its `ca_fp` or its TXT `fp` is not the code of its CA.
  static const mismatch = 'mismatch';

  /// Its certificate does not chain to that CA, or does not name the
  /// gateway's host.
  static const chain = 'chain';
}

/// *It matches · trust `<site>`* (ADR 0050 §2.3, *Trust*): pins the CA of
/// the row [found] for its origin and its standby's.
///
/// 1. `/api/info` once more with the accept-any client (no secret is sent):
///    the CA must be the one whose code the person compared, and its code
///    must be what the gateway claims (`ca_fp`) and announced (`fp`).
/// 2. `/api/info` with the new pin alone: the gateway's certificate must
///    chain to that CA and name the URL's host.
/// 3. The pins go to `discovery.pins` (stored by the persistor); every later
///    connection to that origin trusts that CA and nothing else.
///
/// A refusal pins nothing and leaves the card with the reason.
class TrustGatewayAction extends Action with NonReentrant, WaitingAction {
  TrustGatewayAction(this.found);

  /// The site of the row (`discovery.found` key).
  final String found;

  @override
  Future<AppState?> reduce() async {
    final row = discovery.found[found];
    final url = row?.url;
    if (row == null || url == null || row.code == null) {
      return null;
    }
    final base = Uri.parse(url);
    final GatewayInfo info;
    try {
      info = await deps.gatewayInfo.readUnverified(
        base,
        connectTo: row.connectTo,
      );
    } on InfoFailure {
      return _refused(TrustRefusal.noAnswer);
    }
    final ca = info.ca;
    final code = ca == null ? null : caCode(ca);
    if (code == null || code != row.code) {
      return _refused(TrustRefusal.changed);
    }
    // The TXT `fp` was checked against the same code when the row was made.
    if (info.caFp != null && info.caFp!.toLowerCase() != code) {
      return _refused(TrustRefusal.mismatch);
    }
    final pins = pinsFor(row.copyWith(ca: base64Encode(ca!)));
    try {
      await deps.gatewayInfo.read(
        base,
        // The new pin alone decides for this origin.
        trust: GatewayTrust(discovery.pins).plus(pins),
        connectTo: row.connectTo,
      );
    } on InfoFailure {
      return _refused(TrustRefusal.chain);
    }
    return state.copyWith.discovery(
      pins: discovery.pins.addAll(IMap({for (final p in pins) p.origin: p})),
      found: discovery.found.add(found, row.copyWith(known: true)),
      trustPending: null,
      trustRefused: null,
    );
  }

  AppState _refused(String why) =>
      state.copyWith.discovery(trustPending: found, trustRefused: why);
}
