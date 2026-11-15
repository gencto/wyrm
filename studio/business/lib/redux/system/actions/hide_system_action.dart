import 'package:models/sys_value.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/unwatch_keys_action.dart';
import 'show_system_action.dart';

/// System leaves the screen: its keys are unwatched, and what the ACL
/// counter was is kept, so the attention panel says when it has grown by
/// the next visit. One state at the end; the unwatch notifies nothing of
/// its own (`notify: false`).
class HideSystemAction extends Action {
  @override
  AppState? reduce() {
    final acl = sysStatus[SysValue.aclDenied];
    dispatchSync(UnwatchKeysAction(systemKeys(site.root)), notify: false);
    return state.copyWith.system(
      shown: false,
      aclSeen: acl == null ? state.system.aclSeen : acl.toInt(),
    );
  }
}
