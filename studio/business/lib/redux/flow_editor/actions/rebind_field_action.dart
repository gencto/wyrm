import 'package:models/port_end.dart';

import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'rebind_edge_action.dart';

/// The end of the wire into [from] dragged onto the input [to]: the wire
/// moves; a typed parameter it leaves keeps the last value it showed.
class RebindFieldAction extends Action {
  RebindFieldAction(this.from, this.to);

  /// The input the wire left.
  final PortEnd from;

  /// The input it goes into.
  final PortEnd to;

  @override
  AppState? reduce() {
    final ed = flowEditor;
    final old = ed.base.fields[from.block]
        ?.where((f) => f.inPort == from.port)
        .firstOrNull;
    final last = old == null || !old.typed
        ? null
        : shownValueAt(state, ed.route ?? newFlowId, from.block, old.id);
    dispatchSync(
      RebindEdgeAction(
        from.block,
        from.port,
        to.block,
        to.port,
        param: old?.spec?.name,
        keep: last?.value,
      ),
    );
    return null;
  }
}
