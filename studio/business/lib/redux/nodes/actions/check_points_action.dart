import '../../../wyrm/explorer.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Changes which rows of the points table are checked (docs/design/specs/
/// explorer.md §6): the checkbox or ⌘-click toggles one, Shift-click checks
/// the range from the last row touched, the header checks every row that
/// passes the filter (or unchecks them when all are checked). The rows are
/// the ones on screen when the action runs ([ExplorerView.pointOrder]).
class CheckPointsAction extends Action {
  /// Checks or unchecks [key].
  CheckPointsAction.toggle(String this.key) : _range = false, _all = false;

  /// Checks the rows on screen from the anchor to [key].
  CheckPointsAction.range(String this.key) : _range = true, _all = false;

  /// Checks every row on screen, or unchecks them when all are checked.
  CheckPointsAction.all() : key = null, _range = false, _all = true;

  final String? key;
  final bool _range;
  final bool _all;

  @override
  AppState? reduce() {
    final checked = nodes.checked;
    final order = _all || _range
        ? ExplorerView(state).pointOrder
        : const <String>[];
    if (_all) {
      final every = order.isNotEmpty && order.every(checked.contains);
      return state.copyWith.nodes(
        checked: every ? checked.removeAll(order) : checked.addAll(order),
      );
    }
    final k = key!;
    if (!_range) {
      return state.copyWith.nodes(
        checked: checked.contains(k) ? checked.remove(k) : checked.add(k),
        anchor: k,
      );
    }
    final to = order.indexOf(k);
    if (to < 0) {
      return null;
    }
    final from = order.indexOf(nodes.anchor ?? k);
    final (a, b) = from < 0 ? (to, to) : (from < to ? (from, to) : (to, from));
    return state.copyWith.nodes(
      checked: checked.addAll(order.sublist(a, b + 1)),
    );
  }
}
