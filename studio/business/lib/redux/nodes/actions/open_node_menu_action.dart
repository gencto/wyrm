import 'dart:async';

import '../../app_state.dart';
import '../../common/action.dart';
import 'select_node_action.dart';

/// The node menu of [key] (tree `⋯`, right click, Actions ▾): the node is
/// selected, and the menu opens once its `~meta` is read (its actions are
/// the menu). The read is the one the selection starts; this waits for it
/// to answer or to fail, in `Wait` so the screen can say so. A failed read
/// opens no menu (the node shows `read failed`).
class OpenNodeMenuAction extends Action with WaitingAction {
  OpenNodeMenuAction(this.key);

  final String key;

  bool _read(AppState s) =>
      s.nodes.detail.containsKey(key) || s.nodes.metaFailed.containsKey(key);

  @override
  Future<AppState?> reduce() async {
    if (key != nodes.selectedNode) {
      dispatchSync(SelectNodeAction(key));
    }
    if (!_read(state)) {
      try {
        // The read has its own timeout and then fails; this only ends the
        // wait should no answer ever be kept.
        await waitCondition(_read, timeoutMillis: 60000);
      } on TimeoutException {
        return null;
      }
    }
    if (!nodes.detail.containsKey(key)) {
      return null;
    }
    return state.copyWith.nodes(menu: key);
  }
}
