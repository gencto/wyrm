import 'package:models/json_value.dart';

import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'set_block_param_action.dart';

/// `Save` of the scope prompt (spec §17): [scope] goes into the scope
/// parameter of the block the prompt was opened on, and the prompt closes.
class SaveScopePromptAction extends Action {
  SaveScopePromptAction(this.scope);

  final String scope;

  @override
  AppState? reduce() {
    final ed = flowEditor;
    final block = ed.scopePrompt;
    final b = block == null ? null : ed.draft?.blocks[block];
    final keyed = scopedKeyOf(ed.base.types[b?.type]);
    if (b != null && keyed != null) {
      dispatchSync(
        SetBlockParamAction(b.id, keyed.scope, JsonText(scope)),
        notify: false,
      );
    }
    return state.copyWith.flowEditor(scopePrompt: null);
  }
}
