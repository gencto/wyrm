import '../../app_state.dart';
import '../../common/action.dart';

/// Stops the download that runs: it ends before its next part and the
/// file written so far is removed.
class CancelDownloadAction extends Action {
  @override
  AppState reduce() => state.copyWith.backups(downloading: null);
}
