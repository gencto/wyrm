import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// The welcome's reads its deadline reached before they started
/// (`OpenTreeAction`): each is started and not waited for, so Studio opens
/// on time and each read notifies when it lands. Changes no state itself.
class StartPreloadReadsAction extends Action {
  StartPreloadReadsAction(this.reads);

  final List<ReduxAction<AppState>> reads;

  @override
  AppState? reduce() {
    for (final read in reads) {
      _start(read);
    }
    return null;
  }

  /// Starts [read] and does not wait for it, as the services' dispatchers
  /// start theirs.
  void _start(ReduxAction<AppState> read) => dispatch(read);
}
