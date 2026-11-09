import '../../app_state.dart';
import '../../common/action.dart';

class SetViewedFieldAction extends Action {
  SetViewedFieldAction(this.viewedField);

  final String? viewedField;

  @override
  AppState reduce() => state.copyWith.flowEditor(viewedField: viewedField);
}
