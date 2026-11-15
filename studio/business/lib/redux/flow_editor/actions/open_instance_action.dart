import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'enter_block_action.dart';

/// `Open inside` of the instance [block] of a custom block (spec §20): the
/// canvas shows the block's inside, running under that instance.
class OpenInstanceAction extends Action {
  OpenInstanceAction(this.block);

  final String block;

  @override
  AppState? reduce() {
    if (blockNameOf(flowEditor.draft?.blocks[block]?.type) case final name?) {
      dispatchSync(EnterBlockAction(name, instance: block));
    }
    return null;
  }
}
