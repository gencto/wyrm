import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../app_state.dart';
import '../../common/action.dart';

/// Esc in Explorer: no row checked, no tree row marked, no point in the
/// inspector.
class ClearSelectionAction extends Action {
  @override
  AppState? reduce() => state.copyWith.nodes(
    checked: const ISetConst({}),
    marked: const ISetConst({}),
    point: null,
    anchor: null,
  );
}
