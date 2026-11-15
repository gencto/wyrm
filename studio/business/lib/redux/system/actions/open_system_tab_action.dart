import 'package:models/system_tab.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_system_log_action.dart';
import 'set_tab_action.dart';

/// A tab of System is picked; the Log tab reads the log as it opens (when
/// the user may: `config` on `sys`).
///
/// Rebuilds, decided: when the log is read, the tab is set without a
/// notification and the read's wait notifies once with both; otherwise
/// the tab notifies on its own. Picking the tab on screen sets nothing:
/// the Log tab reads again, another changes nothing (`null`).
class OpenSystemTabAction extends Action {
  OpenSystemTabAction(this.tab);

  final SystemTab tab;

  @override
  Future<AppState?> reduce() async {
    final read = tab == SystemTab.log && sysConfigReason == null;
    if (tab != system.tab) {
      dispatchSync(SetTabAction(tab), notify: !read);
    }
    if (read) {
      await dispatchAndWait(RetrieveSystemLogAction());
    }
    return null;
  }
}
