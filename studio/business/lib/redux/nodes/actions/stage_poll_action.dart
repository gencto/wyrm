import '../../../wyrm/points.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'stage_point_edit_action.dart';

/// Set poll on the checked rows: each one that has an `edit` is staged to
/// poll every [seconds], all in one state.
class StagePollAction extends Action {
  StagePollAction(this.seconds);

  final double seconds;

  @override
  AppState? reduce() {
    var s = state;
    for (final k in nodes.checked) {
      final has =
          s.nodes.detail[k]?.actions.any((a) => a.name == 'edit') ?? false;
      if (!has) {
        continue;
      }
      if (StagePointEditAction.staged(s, k, pollParam, seconds) case final c?) {
        s = s.copyWith(changes: c);
      }
    }
    return identical(s, state) ? null : s;
  }
}
