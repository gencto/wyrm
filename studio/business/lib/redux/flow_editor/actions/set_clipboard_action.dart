import '../../app_state.dart';
import '../../common/action.dart';

class SetClipboardAction extends Action {
  SetClipboardAction(this.clipboard);

  final String? clipboard;

  @override
  AppState reduce() => state.copyWith.flowEditor(clipboard: clipboard);
}
