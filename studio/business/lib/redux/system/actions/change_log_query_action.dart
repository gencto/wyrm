import '../../app_state.dart';
import '../../common/action.dart';
import 'retrieve_system_log_action.dart';

/// A control of the Log toolbar changed ([change]: the source, the level,
/// the filter, the lines, `every 5 s`), and the log is read again with the
/// new arguments when [read] (and the user may: `config` on `sys`).
///
/// The change is in the store before the read starts, so `get_log` takes
/// the new arguments. Rebuilds, decided: with a read, [change] notifies
/// nothing (`notify: false`) and the read's wait notifies once with both;
/// without one, [change] notifies on its own.
class ChangeLogQueryAction extends Action {
  ChangeLogQueryAction(this.change, {this.read = true});

  final Action change;
  final bool read;

  @override
  Future<AppState?> reduce() async {
    final reads = read && sysConfigReason == null;
    dispatchSync(change, notify: !reads);
    if (reads) {
      await dispatchAndWait(RetrieveSystemLogAction());
    }
    return null;
  }
}
