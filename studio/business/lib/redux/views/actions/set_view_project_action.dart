import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// The *Project* switch: the sample's manifest around its pages, from the
/// home page.
class SetViewProjectAction extends Action with SyncsView {
  SetViewProjectAction({required this.on});

  final bool on;

  @override
  AppState? reduce() {
    if (on == views.project) {
      return null;
    }
    syncView = resetView = true;
    return state.copyWith.views(project: on, stack: const .empty());
  }
}
