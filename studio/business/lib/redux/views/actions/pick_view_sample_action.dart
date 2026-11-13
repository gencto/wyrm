import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// Shows the sample [name] from its first message: no refine turn, the
/// project's home page.
class PickViewSampleAction extends Action with SyncsView {
  PickViewSampleAction(this.name);

  final String name;

  @override
  AppState? reduce() {
    final sample = viewSamples[name];
    if (sample == null) {
      return null;
    }
    syncView = resetView = true;
    return state.copyWith.views(
      sample: name,
      source: views.docs[sample.doc] ?? '',
      refine: '',
      project: views.project && sample.project != null,
      stack: const .empty(),
      result: null,
    );
  }
}
