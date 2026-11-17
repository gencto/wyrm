import '../../../wyrm/flow_view/flow_view.dart';
import '../../app_state.dart';
import '../../common/action.dart';
import '../../live/actions/watch_keys_action.dart';
import '../../nodes/actions/retrieve_details_action.dart';
import '../../nodes/actions/retrieve_nodes_action.dart';
import 'load_flow_action.dart';
import 'preview_flow_action.dart';
import 'retrieve_block_library_action.dart';
import 'validate_flow_action.dart';
import 'watch_flow_action.dart';

/// The flow editor opens on route [routeId] (`newFlowId`: a new flow): what
/// it shows is followed at once (`FollowFlowEditorAction` keeps it so),
/// the flow is read, and then its live values, its preview, the site's
/// tree, the library of custom blocks and the actions its blocks run are
/// asked for; last, the engine checks the draft.
class OpenFlowEditorAction extends Action {
  OpenFlowEditorAction(this.routeId);

  final String routeId;

  @override
  Future<AppState?> reduce() async {
    // What the first view shows is followed before the read: the editor's
    // keys stay watched until it closes (`CloseFlowEditorAction`). Nothing
    // on the screen shows it: the read that follows builds the page.
    dispatchSync(
      WatchKeysAction(flowViewOf(state, routeId).follow.watch),
      notify: false,
    );
    final isNew = routeId == newFlowId;
    final load = LoadFlowAction(
      isNew ? '' : routeId,
      isNew: isNew,
      route: routeId,
    );
    await dispatchAndWait(load);
    // Another flow was opened before this one answered: its own open
    // watches, previews and checks it. Nothing of this route follows, or
    // the watch and the preview of the flow left would land over the one
    // on screen.
    if (load.replaced) {
      return null;
    }
    // The deployed version's live values (ADR 0038 §3); a draft that
    // differs from it runs as a preview (`dataflows` ▸ `preview`). One
    // rebuild for both: the watch quietly, the preview's state shown.
    dispatchSync(WatchFlowAction(isNew ? null : routeId), notify: false);
    dispatchSync(PreviewFlowAction());
    // The reads the page needs, at once, each with its own state; the
    // editor is open when they have answered.
    final details = flowViewOf(state, routeId).follow.details;
    await Future.wait([
      // The Tree tab draws the site's live tree: its lists open like the
      // Explorer's.
      if (nodes.expanded.isEmpty)
        dispatchAndWait(RetrieveNodesAction(quiet: true)),
      // Custom blocks: whether this broker has them, and the library.
      dispatchAndWait(RetrieveBlockLibraryAction()),
      // What the actions of the flow's action blocks take.
      if (details.isNotEmpty)
        dispatchAndWait(RetrieveDetailsAction(details.toList())),
      dispatchAndWait(ValidateFlowAction()),
    ]);
    return null;
  }
}
