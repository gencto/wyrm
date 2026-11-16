import 'package:models/block_cfg_key.dart';
import 'package:models/block_type.dart';
import 'package:models/port_end.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'add_block_action.dart';

/// A point of the Tree tab ([key], a full key) dropped on the input [into]
/// (spec §18): a `subscribe` of it, placed left of the block, wired in.
class DropPointOnInputAction extends Action {
  DropPointOnInputAction(this.key, this.into);

  final String key;
  final PortEnd into;

  @override
  AppState? reduce() {
    final target = flowEditor.draft?.blocks[into.block];
    if (target == null) {
      return null;
    }
    dispatchSync(
      AddBlockAction(
        KnownBlock.subscribe.type,
        (target.x - 260).clamp(0, double.infinity).toDouble(),
        target.y,
        cfg: {BlockCfgKey.key.wire: relativeKey(key)},
        into: into,
      ),
    );
    return null;
  }
}
