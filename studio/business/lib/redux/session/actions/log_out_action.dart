import '../../app_state.dart';
import '../../common/action.dart';

/// Ends the session (docs/studio.md §5.1): closes every subscription and the
/// client, and empties every slice the broker filled. Theme, language and the
/// last gateway and user stay; the auth guard sees the token go and shows the
/// log-in page.
class LogOutAction extends Action with WaitingAction {
  @override
  Future<AppState> reduce() async {
    await deps.detach();
    final initial = AppState.initial();
    return initial.copyWith(
      theme: state.theme,
      language: state.language,
      connectivity: state.connectivity,
      wait: state.wait,
      login: state.login.copyWith(password: null),
    );
  }
}
