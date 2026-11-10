import 'package:async_redux/async_redux.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'dismiss_toast_action.dart';

/// *Try again* (or *Refresh*, with [refresh]) of the problem [id]:
/// dispatches the action it carries again, with a fresh token. Its toast
/// goes; a new failure is a new toast.
class RetryProblemAction extends Action {
  RetryProblemAction(this.id, {this.refresh = false});

  final int id;
  final bool refresh;

  @override
  Future<AppState?> reduce() async {
    final e = problems.items.where((e) => e.id == id).firstOrNull;
    final make = refresh ? e?.reload : e?.retry;
    if (make == null) {
      return null;
    }
    dispatchSync(DismissToastAction(id));
    if (make() case final ReduxAction<AppState> action) {
      await dispatchAndWait(action);
    }
    return null;
  }
}
