import '../../app_state.dart';
import '../../common/action.dart';

class SetSelectedLinkAction extends Action {
  SetSelectedLinkAction(this.selectedLink);

  final String? selectedLink;

  @override
  AppState reduce() => state.copyWith.links(selectedLink: selectedLink);
}
