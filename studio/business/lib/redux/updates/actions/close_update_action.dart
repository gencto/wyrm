import '../../app_state.dart';
import '../../common/action.dart';
import '../models/updates_state.dart';

/// Closes the update sheet. An update that runs goes on in the broker; the
/// sheet shows it again when it is opened.
class CloseUpdateAction extends Action {
  @override
  AppState reduce() => state.copyWith(updates: const UpdatesState());
}
