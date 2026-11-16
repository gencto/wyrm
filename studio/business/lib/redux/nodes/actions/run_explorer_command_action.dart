import 'package:models/explorer_command.dart';

import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'invoke_node_action.dart';
import 'remove_checked_action.dart';
import 'set_action_action.dart';

/// A button of Explorer's header, toolbar or selection bar, run on the node
/// on screen as it is when the button is pressed (the name of its import
/// action, the checked rows): one action for the press, which starts the
/// one step the button stands for, and ends with it (a ping ends with its
/// answer). Nothing on screen: nothing runs.
class RunExplorerCommandAction extends Action {
  RunExplorerCommandAction(this.command);

  final ExplorerCommand command;

  @override
  Future<AppState?> reduce() async {
    final x = ExplorerView(state);
    final sel = x.selected;
    if (sel == null) {
      return null;
    }
    switch (command) {
      case ExplorerCommand.ping:
        // It has its own waiting state; its answer comes in its own state.
        await dispatchAndWait(InvokeNodeAction(sel, 'ping'));
      case ExplorerCommand.addPoint:
        dispatchSync(SetActionAction('add_point'));
      case ExplorerCommand.importPoints:
        dispatchSync(SetActionAction(x.importAction));
      case ExplorerCommand.removeChecked:
        dispatchSync(RemoveCheckedAction());
    }
    return null;
  }
}
