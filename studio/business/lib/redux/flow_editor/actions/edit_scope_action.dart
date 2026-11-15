import 'package:models/field_id.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_scope_prompt_action.dart';

/// The pencil of the row [row] of block [block]: on its `Scope` row it
/// opens the scope prompt (spec §17).
class EditScopeAction extends Action {
  EditScopeAction(this.block, this.row);

  final String block;
  final RowId row;

  @override
  AppState? reduce() {
    final base = flowEditor.base;
    final keyed = scopedKeyOf(base.types[base.draft?.blocks[block]?.type]);
    if (keyed == null || row != keyed.scopeField) {
      return null;
    }
    dispatchSync(SetScopePromptAction(block));
    return null;
  }
}
