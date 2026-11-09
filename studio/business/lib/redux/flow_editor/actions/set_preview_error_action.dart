import '../../app_state.dart';
import '../../common/action.dart';

class SetPreviewErrorAction extends Action {
  SetPreviewErrorAction(this.previewError);

  final String? previewError;

  @override
  AppState reduce() => state.copyWith.flowEditor(previewError: previewError);
}
