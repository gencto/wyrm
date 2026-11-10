import '../../app_state.dart';
import '../../common/action.dart';

/// The toast [id] (of a problem or a notice) is closed or its time is up.
/// The problem stays in Problems.
class DismissToastAction extends Action {
  DismissToastAction(this.id);

  final int id;

  @override
  AppState? reduce() {
    final p = state.problems;
    if (!p.toasts.contains(id) && !p.notices.any((n) => n.id == id)) {
      return null;
    }
    return state.copyWith.problems(
      toasts: p.toasts.remove(id),
      notices: p.notices.removeWhere((n) => n.id == id),
    );
  }
}
