import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'stage_invoke_action.dart';

/// Remove… on the checked rows: a `remove` of each is staged and the
/// selection is cleared, in one state.
class RemoveCheckedAction extends Action {
  @override
  AppState? reduce() {
    final checked = nodes.checked;
    if (checked.isEmpty) {
      return null;
    }
    for (final k in checked) {
      dispatchSync(StageInvokeAction(k, 'remove', const {}), notify: false);
    }
    return state.copyWith.nodes(
      checked: const ISetConst({}),
      marked: const ISetConst({}),
      point: null,
      anchor: null,
    );
  }
}
