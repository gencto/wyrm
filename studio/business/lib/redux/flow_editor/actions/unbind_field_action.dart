import 'package:models/field_id.dart';

import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'disconnect_edge_action.dart';

/// `Unbind` of the field [row] of block [block]: its wire goes; a typed
/// parameter keeps the last value it showed.
class UnbindFieldAction extends Action {
  UnbindFieldAction(this.block, this.row);

  final String block;
  final RowId row;

  @override
  AppState? reduce() {
    final row = this.row;
    if (row is! FieldId) {
      return null;
    }
    final ed = flowEditor;
    final f = ed.base.fields[block]?.where((x) => x.id == row).firstOrNull;
    final port = f?.inPort;
    if (f == null || port == null) {
      return null;
    }
    final last = shownValueAt(state, ed.route ?? newFlowId, block, row);
    dispatchSync(
      DisconnectEdgeAction(
        block,
        port,
        param: f.spec?.name,
        keep: f.typed ? last?.value : null,
      ),
    );
    return null;
  }
}
