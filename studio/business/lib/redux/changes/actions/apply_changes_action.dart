import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Applies the staged changes in the order they were staged, each with the
/// user's own rights: a `set` of the key, or an `invoke` of its action.
///
/// It stops at the first refusal: what was applied leaves the list, the
/// refused change and the ones after it stay, and the broker's message is
/// kept in `changes.message` for the review panel.
class ApplyChangesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final api = deps.wyrm;
    final done = <String>{};
    String? message;
    for (final id in changes.view) {
      final c = changes.table[id];
      if (c == null) {
        continue;
      }
      try {
        if (c.action case final action?) {
          await api
              .invoke(c.key, action, Value.from(c.args.unlock))
              .drain<void>();
        } else {
          await api.set(c.key, Value.from(c.value));
        }
        done.add(id);
      } on WyrmException catch (e) {
        message = '${c.key}: ${e.status.name}: ${e.message}';
        break;
      }
    }
    return state.copyWith.changes(
      table: changes.table.removeWhere((k, _) => done.contains(k)),
      view: changes.view.removeWhere(done.contains),
      message: message,
      open: message != null,
    );
  }
}
