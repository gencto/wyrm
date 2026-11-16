import 'package:models/field_id.dart';
import 'package:models/port_end.dart';

import '../../../wyrm/mappers/block_cfg.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'connect_ports_action.dart';
import 'set_block_param_action.dart';

/// A wire dragged from [from] and let go on the field [row] of block
/// [block] in the inspector binds it. An argument the action has and the
/// block not yet gets its key first, so that the port exists.
class BindFieldAction extends Action {
  BindFieldAction(this.block, this.row, this.from);

  final String block;
  final RowId row;
  final PortEnd from;

  @override
  AppState? reduce() {
    final base = flowEditor.base;
    final b = base.draft?.blocks[block];
    final f = base.fields[block]?.where((x) => x.id == row).firstOrNull;
    final port = f?.inPort;
    if (b == null || f == null || port == null || from.block == b.id) {
      return null;
    }
    if (f.kind == FieldKind.arg && !b.cfgArgs.containsKey(f.name)) {
      dispatchSync(
        SetBlockParamAction(b.id, BlockCfgKey.args.wire, {
          ...rawFields(b.cfgArgs),
          f.name: null,
        }),
        notify: false,
      );
    }
    final before = state;
    dispatchSync(
      ConnectPortsAction(from.block, from.port, b.id, port),
      notify: false,
    );
    // The key and the wire are drawn together, once.
    return identical(state, before) ? null : state;
  }
}
