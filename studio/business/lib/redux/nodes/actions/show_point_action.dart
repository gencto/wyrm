import '../../app_state.dart';
import '../../common/action.dart';

/// The point [key] in the inspector, the node on screen staying; null
/// shows the node itself (docs/design/specs/explorer.md §4 "nothing
/// selected"). It reads nothing (`SelectPointAction` does).
class ShowPointAction extends Action {
  ShowPointAction(this.key);

  final String? key;

  @override
  AppState? reduce() => key == nodes.point
      ? null
      : state.copyWith.nodes(point: key, anchor: key ?? nodes.anchor);
}
