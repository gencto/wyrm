import '../../app_state.dart';
import '../../common/action.dart';

class SetCategoryAction extends Action {
  SetCategoryAction(this.category);

  final String category;

  @override
  AppState reduce() => state.copyWith.linkInstall(category: category);
}
