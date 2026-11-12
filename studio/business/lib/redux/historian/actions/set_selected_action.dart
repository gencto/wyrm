import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';
import 'follow_history_action.dart';

/// Selects the watch group [selected]; another group starts with no point
/// picked.
class SetSelectedAction extends Action {
  SetSelectedAction(this.selected);

  final String? selected;

  @override
  AppState reduce() => selected == historian.selected
      ? state
      : state.copyWith.historian(
          selected: selected,
          points: const IListConst([]),
          series: const IMapConst({}),
        );

  /// While History is shown, its subscriptions follow the new group.
  @override
  void after() {
    super.after();
    dispatchSync(FollowHistoryAction());
  }
}
