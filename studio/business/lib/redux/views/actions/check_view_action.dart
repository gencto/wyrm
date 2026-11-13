import 'package:fast_immutable_collections/fast_immutable_collections.dart';

import '../../../wyrm/views/view_check.dart';
import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';

/// Runs the checks of the document on screen with what is known of its
/// keys now.
class CheckViewAction extends Action {
  @override
  AppState? reduce() {
    final checks = checkView(
      viewNow(state.views).doc,
      views.catalog.unlock,
      views.keys.unlock,
      views.grants.unlock,
    ).lock;
    return checks == views.checks ? null : state.copyWith.views(checks: checks);
  }
}
