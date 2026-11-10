import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/mappers/log_line_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// `sys` ▸ `get_log {lines, level?, filter?, link?}` (config): the broker's
/// last log lines into `system.log`, newest first. The arguments are the
/// Log toolbar's: `system.lines`, `logLevel`, `filter` and `source` (an
/// embedded link's id; none = the whole broker).
///
/// Dispatched by `Get log`, by a change of the toolbar and when the tab is
/// shown; the repeat every 5 s is `PollSystemLogAction`.
class RetrieveSystemLogAction extends Action with WaitingAction {
  @override
  Future<AppState?> reduce() => readSystemLog(this);
}

/// One `get_log` with the toolbar's arguments.
///
/// A refusal is not a dialog: its message goes to `system.logError` and the
/// log box shows it (specs/system.md, States), so a read repeated every 5 s
/// cannot pile dialogs up. The lines held stay.
Future<AppState?> readSystemLog(Action a) async {
  final root = a.site.root;
  if (root == null) {
    return null;
  }
  final system = a.system;
  try {
    final rows = await a.deps.wyrm
        .invoke(
          '$root/sys',
          'get_log',
          Value.from({
            'lines': system.lines,
            'level': ?system.logLevel,
            if (system.filter case final f? when f.isNotEmpty) 'filter': f,
            if (system.source case final l? when l.isNotEmpty) 'link': l,
          }),
        )
        .toList();
    return a.state.copyWith.system(
      log: logLinesOf(rows).reversed.toList().lock,
      logError: null,
    );
  } on WyrmException catch (e) {
    return a.state.copyWith.system(logError: '${e.status.name}: ${e.message}');
  }
}
