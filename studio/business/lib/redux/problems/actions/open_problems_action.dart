import '../../app_state.dart';
import '../../common/action.dart';

/// Opens or closes the Problems drawer; opening it clears the counter
/// (the pill counts the problems not yet looked at).
class OpenProblemsAction extends Action {
  OpenProblemsAction({this.open = true});

  final bool open;

  @override
  AppState reduce() => state.copyWith.problems(
    open: open,
    unread: open ? 0 : state.problems.unread,
  );
}
