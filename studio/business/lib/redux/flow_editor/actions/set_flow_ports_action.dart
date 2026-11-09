import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Live values of the deployed flow's ports and parameters from its watch
/// (ADR 0038 §3); [reset] drops the ones held before.
class SetFlowPortsAction extends Action {
  SetFlowPortsAction(this.changed, {this.reset = false});

  final Map<String, LiveValue> changed;
  final bool reset;

  @override
  AppState? reduce() {
    if (changed.isEmpty && (!reset || flowEditor.ports.isEmpty)) {
      return null;
    }
    final base = reset ? flowEditor.ports.clear() : flowEditor.ports;
    return state.copyWith.flowEditor(ports: base.addAll(changed.lock));
  }
}
