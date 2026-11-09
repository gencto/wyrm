import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:wyrm_client/wyrm_client.dart';

import '../../../wyrm/calls.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../links/actions/get_link_log_action.dart';

/// `sys` ▸ `get_log {lines, level?, filter?}` (config): the broker's last
/// log lines into `system.log`.
class RetrieveSystemLogAction extends Action with WaitingAction {
  RetrieveSystemLogAction({this.lines = 300});

  final int lines;

  @override
  Future<AppState> reduce() async {
    final rows = await invokeAll(
      deps.wyrm,
      '${site.root}/sys',
      'get_log',
      Value.from({
        'lines': lines,
        'level': ?system.logLevel,
        if (system.filter case final f? when f.isNotEmpty) 'filter': f,
      }),
    );
    return state.copyWith.system(log: logLines(rows).reversed.toList().lock);
  }
}
