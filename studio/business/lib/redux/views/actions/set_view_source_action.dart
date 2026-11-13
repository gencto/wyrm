import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// Shows pasted JSONL in place of a sample.
class SetViewSourceAction extends Action with SyncsView {
  SetViewSourceAction(this.text);

  final String text;

  @override
  AppState? reduce() {
    syncView = resetView = true;
    return state.copyWith.views(
      sample: 'pasted',
      source: text,
      refine: '',
      project: false,
      stack: const .empty(),
      result: null,
    );
  }
}
