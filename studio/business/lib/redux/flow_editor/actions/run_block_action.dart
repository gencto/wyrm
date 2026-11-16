import 'package:async_redux/async_redux.dart';
import 'package:models/field_id.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../../wyrm/mappers/flow_fields.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'trigger_block_action.dart';

/// `Run` of the row [row] of the selected block (spec §19): an unbound
/// `Trigger` runs the block once in the deployed flow, by the id the engine
/// knows it by (`<instance>/<inner>` inside a custom block). A block opened
/// from the palette runs nowhere.
class RunBlockAction extends Action {
  RunBlockAction(this.row);

  final RowId row;

  @override
  AppState? reduce() {
    final sel = flowEditor.selectedBlock;
    final node = sel == null ? null : engineIdOf(flowEditor.frames, sel);
    if (node != null && row == FieldId.input(EnginePort.trigger.wire)) {
      // The broker's own call; a refusal comes as an error.
      _start(TriggerBlockAction(node));
    }
    return null;
  }

  /// Starts [action] and does not wait for it: it brings its own state
  /// (and its own waiting state, where it has one).
  void _start(ReduxAction<AppState> action) => dispatch(action);
}
