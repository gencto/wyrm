import '../../app_state.dart';
import '../../common/action.dart';

class SetQueryAction extends Action {
  SetQueryAction(this.query);

  final String query;

  @override
  AppState reduce() => state.copyWith.flows(query: query);
}
