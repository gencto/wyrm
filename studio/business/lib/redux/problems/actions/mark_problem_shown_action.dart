import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The problem [id] was opened as a dialog: the drawer says so, and its
/// toast (if it had one) is gone.
class MarkProblemShownAction extends Action {
  MarkProblemShownAction(this.id);

  final int id;

  @override
  AppState? reduce() {
    final p = state.problems;
    if (!p.items.any((e) => e.id == id && !e.shown)) {
      return null;
    }
    return state.copyWith.problems(
      items: p.items
          .map((e) => e.id == id ? e.copyWith(shown: true) : e)
          .toIList(),
      toasts: p.toasts.remove(id),
    );
  }
}
