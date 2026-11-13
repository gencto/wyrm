import '../../../wyrm/views/view_now.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import 'check_view_action.dart';

/// Points the bridge at the document on screen: it subscribes what the
/// document reads and closes the rest. With [reset] the surface is another
/// one, so the values of the last one are dropped (the bridge writes again
/// what it still holds).
class SyncViewAction extends Action {
  SyncViewAction({this.reset = false});

  final bool reset;

  @override
  AppState? reduce() {
    final now = viewNow(state.views);
    deps.viewBridge.sync(
      now.bindings,
      menu: now.project?.listed ?? const {},
      root: now.root,
    );
    dispatchSync(CheckViewAction());
    return reset ? state.copyWith.views(data: const .empty()) : null;
  }
}

/// An action after which the bridge follows the document again: the sync
/// runs once the action's own state is in the store.
mixin SyncsView on Action {
  /// Set in `reduce` when the document on screen changed.
  var syncView = false;

  /// The surface is another one: its values are dropped.
  var resetView = false;

  @override
  void after() {
    super.after();
    if (syncView) {
      dispatchSync(SyncViewAction(reset: resetView));
    }
  }
}
