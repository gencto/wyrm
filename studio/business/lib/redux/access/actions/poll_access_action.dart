import 'package:async_redux/async_redux.dart';
import 'package:logging/logging.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_access_action.dart';

/// Access's `every 10 s` while its tab is shown: `/api/users` has no
/// stream, so users made, changed or removed elsewhere (another Studio, an
/// assistant through the gateway) come in this way, with the grants and
/// the audit tail.
///
/// The same read as `RetrieveAccessAction`, but not in `Wait` (no sweep
/// bar every ten seconds) and silent: a failed poll keeps what is shown
/// and the next one tries again, so a gateway that is down raises no
/// dialog or toast per tick (the shell's offline banner says it). It does
/// nothing while the tab is hidden or a read is in flight, and one poll
/// at a time runs.
class PollAccessAction extends Action with NonReentrant {
  static final _log = Logger('PollAccessAction');

  @override
  Future<AppState?> reduce() async {
    if (!access.shown || access.isWaiting) {
      return null;
    }
    try {
      return await readAccess(this);
    } on Object catch (e) {
      // Logged, not shown: see the class comment.
      _log.fine('poll access: $e');
      return null;
    }
  }
}
