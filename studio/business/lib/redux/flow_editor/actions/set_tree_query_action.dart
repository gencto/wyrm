import '../../app_state.dart';
import '../../common/action.dart';

class SetTreeQueryAction extends Action {
  SetTreeQueryAction(this.treeQuery);

  final String treeQuery;

  @override
  AppState reduce() => state.copyWith.flowEditor(treeQuery: treeQuery);
}
