import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/live_value.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Live values of the draft from its preview: [ports] keyed as the watch's,
/// [sinks] by node (what it would write); [reset] drops the ones held
/// before.
class SetFlowPreviewAction extends Action {
  SetFlowPreviewAction(this.ports, this.sinks, {this.reset = false});

  final Map<String, LiveValue> ports;
  final Map<String, LiveValue> sinks;
  final bool reset;

  @override
  AppState? reduce() {
    final ed = flowEditor;
    if (ports.isEmpty &&
        sinks.isEmpty &&
        (!reset || (ed.previewPorts.isEmpty && ed.previewSinks.isEmpty))) {
      return null;
    }
    return state.copyWith.flowEditor(
      previewPorts: (reset ? ed.previewPorts.clear() : ed.previewPorts).addAll(
        ports.lock,
      ),
      previewSinks: (reset ? ed.previewSinks.clear() : ed.previewSinks).addAll(
        sinks.lock,
      ),
    );
  }
}
