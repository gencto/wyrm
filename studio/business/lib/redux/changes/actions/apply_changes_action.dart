import 'dart:async';

import 'package:wyrm_client/wyrm_client.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../nodes/actions/retrieve_details_action.dart';

/// Applies the staged changes the user has the level for, in the order they
/// were staged, each with the user's own rights: a `set` of the key, or an
/// `invoke` of its action. A change that needs a level the user lacks stays
/// staged for an admin (the review drawer's `Ask an admin for <m>`).
///
/// It stops at the first refusal: what was applied leaves the list, the
/// refused change and the ones after it stay, and the broker's message is
/// kept in `changes.message` for the review panel. The meta of every key an
/// applied change touched is read again, so the points table shows the new
/// `cfg`.
class ApplyChangesAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() async {
    final api = deps.wyrm;
    final done = <String>{};
    final touched = <String>{};
    String? message;
    for (final id in changes.view) {
      final c = changes.table[id];
      // With no grants read (an old gateway), the broker alone decides.
      if (c == null || (site.grants.isNotEmpty && !site.can(c.level, c.key))) {
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
        touched.add(c.key);
      } on WyrmException catch (e) {
        message = '${c.key}: ${e.status.name}: ${e.message}';
        break;
      }
    }
    if (touched.isNotEmpty) {
      unawaited(
        dispatchAndWait(RetrieveDetailsAction(touched.toList(), force: true)),
      );
    }
    final left = changes.view.removeWhere(done.contains);
    return state.copyWith.changes(
      table: changes.table.removeWhere((k, _) => done.contains(k)),
      view: left,
      message: message,
      open: message != null || (changes.open && left.isNotEmpty),
    );
  }
}
