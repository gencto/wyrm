import '../../../wyrm/decode/block_cfg.dart';
import '../../../wyrm/mappers/flow_blocks.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'disconnect_edge_action.dart';

/// `Cancel` of the scope prompt: no scope, no binding — a key from a wire
/// without one does not compile, so the wire into the key goes. A block
/// that has its scope keeps both.
class CancelScopePromptAction extends Action {
  @override
  AppState? reduce() {
    final ed = flowEditor;
    final block = ed.scopePrompt;
    final b = block == null ? null : ed.draft?.blocks[block];
    final keyed = scopedKeyOf(ed.base.types[b?.type]);
    if (b != null &&
        keyed != null &&
        (b.textOf(keyed.scope)?.trim().isEmpty ?? true)) {
      dispatchSync(DisconnectEdgeAction(b.id, keyed.port), notify: false);
    }
    return state.copyWith.flowEditor(scopePrompt: null);
  }
}
