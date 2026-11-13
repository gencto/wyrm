import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:models/view_place.dart';

import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'sync_view_action.dart';

/// `wyrm.open {page, params}` and a tap in the menu: opens [page] of the
/// project with [params] (full keys). From the menu ([root]) the back
/// stack starts again; from a page it grows by one.
class OpenViewPageAction extends Action with SyncsView {
  OpenViewPageAction(this.page, {this.params = const {}, this.root = false});

  final String page;
  final Map<String, String> params;
  final bool root;

  @override
  AppState? reduce() {
    final project = viewNow(state.views).project;
    if (project == null || project.page(page) == null) {
      return state.copyWith.views(
        result: 'There is no page `$page` to open.',
      );
    }
    final place = ViewPlace(page: page, params: params.lock);
    final home = ViewPlace(page: project.home);
    final stack = root
        ? (place == home ? <ViewPlace>[home] : [home, place])
        : [
            ...views.stack.isEmpty ? [home] : views.stack,
            place,
          ];
    if (stack.lock == views.stack) {
      return null;
    }
    syncView = resetView = true;
    return state.copyWith.views(stack: stack.lock, result: null);
  }
}
