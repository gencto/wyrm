import '../../../wyrm/session.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Asks each gateway of [text] (a comma list, else the gateway field) whether
/// it is there, and keeps how long it took in `login.probes`: milliseconds,
/// or -1 for no answer within 5 s (docs/design/specs/login.md §6). Runs on
/// open, on a recent chip and on leaving the URL field.
class ProbeGatewayAction extends Action with WaitingAction {
  ProbeGatewayAction([this.text]);

  /// The gateways to probe; null probes the field.
  final String? text;

  @override
  Future<AppState?> reduce() async {
    final gateways = parseGateways(text ?? login.gateway ?? '');
    if (gateways.isEmpty) {
      return null;
    }
    final found = await Future.wait([
      for (final g in gateways) deps.login.probe(g),
    ]);
    var probes = state.login.probes;
    for (final (i, p) in found.indexed) {
      probes = probes.add(gatewayKey(gateways[i]), p.ms ?? -1);
    }
    return state.copyWith.login(probes: probes);
  }
}

/// The key of a gateway in `login.probes`: its origin, `scheme://host:port`.
String gatewayKey(Uri gateway) => gateway.origin;
