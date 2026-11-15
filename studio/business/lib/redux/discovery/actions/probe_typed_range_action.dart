import '../../app_state.dart';
import '../../common/action.dart';
import 'probe_range_action.dart';

/// *Probe* under *Probe a range instead* (ADR 0050 §2.3): the range and
/// the port typed (else the /24 around this computer and the field's
/// port), when both are good; a fault is shown under its field and sends
/// nothing.
class ProbeTypedRangeAction extends Action {
  @override
  Future<AppState?> reduce() async {
    final port = discovery.probePort;
    if (discovery.rangeFault != null || port == null) {
      return null;
    }
    await dispatchAndWait(ProbeRangeAction(discovery.rangeText, port));
    return null;
  }
}
