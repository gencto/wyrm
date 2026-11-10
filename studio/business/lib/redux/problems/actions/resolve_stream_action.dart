import '../../app_state.dart';
import '../../common/action.dart';

/// The live streams of the site [of] are open again (every site when null): the
/// toasts that stayed for them go. The lines stay in Problems.
class ResolveStreamAction extends Action {
  ResolveStreamAction([this.of]);

  final String? of;

  @override
  AppState? reduce() {
    final p = state.problems;
    final back = {
      for (final e in p.items)
        if (e.stream != null && (of == null || e.stream == of)) e.id,
    };
    if (!p.toasts.any(back.contains)) {
      return null;
    }
    return state.copyWith.problems(
      toasts: p.toasts.removeWhere(back.contains),
    );
  }
}
