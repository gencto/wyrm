import '../../app_state.dart';
import '../../common/action.dart';

/// The Log toolbar's time (`hh:mm:ss`, UTC as the rows show it): only the
/// lines within two minutes of it are shown (`linesAround`). Null shows
/// them all. Typed by the user, or set by *Open the log* to the time of
/// the error it came from (docs/design/specs/errors.md §3).
class SetAroundAction extends Action {
  SetAroundAction(this.around);

  final String? around;

  @override
  AppState reduce() => state.copyWith.system(around: around);
}
