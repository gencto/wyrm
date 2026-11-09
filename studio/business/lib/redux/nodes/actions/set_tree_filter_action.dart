import '../../app_state.dart';
import '../../common/action.dart';

class SetTreeFilterAction extends Action {
  SetTreeFilterAction(this.treeFilter);

  final String treeFilter;

  @override
  AppState reduce() => state.copyWith.nodes(treeFilter: treeFilter);
}
