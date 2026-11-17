import 'package:models/system_tab.dart';

import '../../../wyrm/mappers/log_line_mapper.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// *Open the log* of an error (errors.md §3): System › Log is the tab, and
/// its time is the time of the error ([at]) on the rows' clock, in one
/// state. `get_log` takes no time: the toolbar's time keeps the lines
/// within two minutes of it, of those read.
class AimLogAction extends Action {
  AimLogAction(this.at);

  /// When the error happened; null: no time to aim at.
  final DateTime? at;

  @override
  AppState reduce() => state.copyWith.system(
    around: switch (at) {
      final t? => logClockOf(t),
      null => null,
    },
    tab: SystemTab.log,
  );
}
