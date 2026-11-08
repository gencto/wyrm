import '../../app_state.dart';
import '../../common/action.dart';

class SetItemAction extends Action {
  SetItemAction(this.item);

  final String? item;

  @override
  AppState reduce() => state.copyWith.linkInstall(item: item);
}
