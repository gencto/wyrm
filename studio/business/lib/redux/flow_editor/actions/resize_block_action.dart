import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'resize_block_ports_action.dart';
import 'resize_inputs_action.dart';

/// The − and + under block [block]: an input (a pair, a case) more or
/// fewer; on the inputs or outputs of a custom block's inside, a port.
class ResizeBlockAction extends Action {
  ResizeBlockAction(this.block, {required this.add});

  final String block;
  final bool add;

  @override
  AppState? reduce() {
    dispatchSync(
      isBoundary(block)
          ? ResizeBlockPortsAction(input: block == blockInputsId, add: add)
          : ResizeInputsAction(block, add: add),
    );
    return null;
  }
}
