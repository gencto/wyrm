import '../../app_state.dart';
import '../../common/action.dart';

class SetPreviewOffAction extends Action {
  SetPreviewOffAction(this.previewOff);

  final String? previewOff;

  @override
  AppState reduce() => state.copyWith.flowEditor(previewOff: previewOff);
}
